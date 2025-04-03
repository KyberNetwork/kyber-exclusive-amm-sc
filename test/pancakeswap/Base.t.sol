// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.t.sol';

import 'src/PancakeSwapInfinityKEMHook.sol';
import 'src/base/BaseKEMHook.sol';

import 'pancakeswap/infinity-core/src/libraries/CustomRevert.sol';
import 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLHooks.sol';
import 'pancakeswap/infinity-core/src/pool-cl/libraries/CLPoolParametersHelper.sol';
import 'pancakeswap/infinity-core/test/helpers/TokenFixture.sol';
import 'pancakeswap/infinity-core/test/pool-cl/helpers/CLPoolManagerRouter.sol';
import 'pancakeswap/infinity-core/test/pool-cl/helpers/Deployers.sol';
import 'pancakeswap/infinity-core/test/pool-cl/helpers/Fuzzers.sol';

contract PancakeSwapHookBaseTest is BaseTest, Deployers, TokenFixture, Fuzzers {
  using CLPoolParametersHelper for bytes32;

  IVault public vault;
  CLPoolManager public manager;
  CLPoolManagerRouter public swapRouter;
  PoolKey keyWithoutHook;
  PoolId idWithoutHook;
  PoolKey keyWithHook;

  CLPoolManagerRouter.SwapTestSettings testSettings =
    CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

  address[] tokens;

  function setUp() public override {
    super.setUp();

    (vault, manager) = createFreshManager();
    swapRouter = new CLPoolManagerRouter(vault, manager);
    deployMintAndApprove2Currencies();
    deployFreshHook();

    tokens = new address[](2);
    tokens[0] = Currency.unwrap(currency0);
    tokens[1] = Currency.unwrap(currency1);
  }

  function deployMintAndApprove2Currencies() internal {
    MockERC20 token0 = deployMintAndApproveToken();
    MockERC20 token1 = deployMintAndApproveToken();

    (currency0, currency1) = SortTokens.sort(token0, token1);
  }

  function deployMintAndApproveToken() internal returns (MockERC20) {
    MockERC20 token = deployTokens(1, 2 ** 255)[0];

    token.approve(address(swapRouter), Constants.MAX_UINT256);

    return token;
  }

  function deployFreshHook() internal {
    hook = IKEMHook(
      new PancakeSwapInfinityKEMHook(
        manager,
        owner,
        newAddressesLength1(operator),
        newAddressesLength1(address(swapRouter)),
        quoteSigner,
        egRecipient
      )
    );
  }

  function initPools(PoolConfig memory poolConfig) internal {
    poolConfig.fee = boundFee(poolConfig.fee);
    poolConfig.tickSpacing = boundTickSpacing(poolConfig.tickSpacing);
    poolConfig.sqrtPriceX96 =
      createRandomSqrtPriceX96(poolConfig.tickSpacing, poolConfig.sqrtPriceX96seed);

    keyWithoutHook = PoolKey(
      currency0,
      currency1,
      IHooks(address(0)),
      manager,
      poolConfig.fee,
      bytes32(0).setTickSpacing(poolConfig.tickSpacing)
    );
    idWithoutHook = keyWithoutHook.toId();
    keyWithHook = PoolKey(
      currency0,
      currency1,
      IHooks(address(hook)),
      manager,
      poolConfig.fee,
      bytes32(uint256(IHooks(address(hook)).getHooksRegistrationBitmap())).setTickSpacing(
        poolConfig.tickSpacing
      )
    );

    manager.initialize(keyWithoutHook, poolConfig.sqrtPriceX96);
    manager.initialize(keyWithHook, poolConfig.sqrtPriceX96);
  }

  function addLiquidity(PositionConfig memory positionConfig) internal {
    ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams({
      tickLower: positionConfig.lowerTick,
      tickUpper: positionConfig.upperTick,
      liquidityDelta: positionConfig.liquidityDelta,
      salt: 0
    });
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    params = createFuzzyLiquidityParamsWithTightBound(keyWithoutHook, params, sqrtPriceX96, 20);

    swapRouter.modifyPosition(keyWithoutHook, params, '');
    swapRouter.modifyPosition(keyWithHook, params, '');
  }

  function boundSwapConfig(SwapConfig memory swapConfig) internal view {
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    boundSwapConfig(swapConfig, sqrtPriceX96);
  }

  function swapWithBothPools(SwapConfig memory swapConfig, bool needClaim)
    internal
    returns (uint256 egAmount)
  {
    boundSwapConfig(swapConfig);

    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    BalanceDelta deltaWithoutHook = swapRouter.swap(keyWithoutHook, params, testSettings, '');
    int128 amountIn;
    int128 amountOutWithoutHook;
    if (swapConfig.zeroForOne) {
      amountIn = -deltaWithoutHook.amount0();
      amountOutWithoutHook = deltaWithoutHook.amount1();
    } else {
      amountIn = -deltaWithoutHook.amount1();
      amountOutWithoutHook = deltaWithoutHook.amount0();
    }

    boundExchangeRateDenom(swapConfig, amountIn, amountOutWithoutHook);

    bytes memory signature = getSignature(
      quoteSignerKey,
      keccak256(
        abi.encode(
          keyWithHook,
          swapConfig.zeroForOne,
          swapConfig.maxAmountIn,
          swapConfig.maxExchangeRate,
          swapConfig.exchangeRateDenom,
          swapConfig.expiryTime
        )
      )
    );
    bytes memory hookData = abi.encode(
      swapConfig.maxAmountIn,
      swapConfig.maxExchangeRate,
      swapConfig.exchangeRateDenom,
      swapConfig.expiryTime,
      signature
    );

    Currency currencyOut = swapConfig.zeroForOne ? currency1 : currency0;
    int256 maxAmountOut = amountIn * swapConfig.maxExchangeRate / swapConfig.exchangeRateDenom;
    egAmount =
      uint256(maxAmountOut < amountOutWithoutHook ? amountOutWithoutHook - maxAmountOut : int256(0));

    BalanceDelta deltaWithHook = swapRouter.swap(keyWithHook, params, testSettings, hookData);
    int128 amountOutWithHook;
    if (swapConfig.zeroForOne) {
      amountOutWithHook = deltaWithHook.amount1();
    } else {
      amountOutWithHook = deltaWithHook.amount0();
    }

    if (egAmount > 0) {
      assertEq(amountOutWithHook, maxAmountOut);
      assertEq(
        vault.balanceOf(address(hook), currencyOut),
        uint256(int256(amountOutWithoutHook - maxAmountOut))
      );
    } else {
      assertEq(amountOutWithHook, amountOutWithoutHook);
    }

    if (needClaim) {
      vm.prank(operator);
      hook.claimEgTokens(tokens, new uint256[](2));
    }
  }

  function swapWithHookOnly(SwapConfig memory swapConfig) internal {
    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    bytes memory signature = getSignature(
      quoteSignerKey,
      keccak256(
        abi.encode(
          keyWithHook,
          swapConfig.zeroForOne,
          swapConfig.maxAmountIn,
          swapConfig.maxExchangeRate,
          swapConfig.exchangeRateDenom,
          swapConfig.expiryTime
        )
      )
    );
    bytes memory hookData = abi.encode(
      swapConfig.maxAmountIn,
      swapConfig.maxExchangeRate,
      swapConfig.exchangeRateDenom,
      swapConfig.expiryTime,
      signature
    );

    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }
}
