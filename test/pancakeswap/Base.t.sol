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
        manager, owner, newAddressesLength1(operator), quoteSigner, egRecipient
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

  function addLiquidity(AddLiquidityConfig memory addLiquidityConfig) internal {
    ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams({
      tickLower: addLiquidityConfig.lowerTick,
      tickUpper: addLiquidityConfig.upperTick,
      liquidityDelta: addLiquidityConfig.liquidityDelta,
      salt: 0
    });
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    params = createFuzzyLiquidityParamsWithTightBound(
      keyWithoutHook, params, sqrtPriceX96, MULTIPLE_TEST_CONFIG_LENGTH
    );

    try swapRouter.modifyPosition(keyWithoutHook, params, '') {
      swapRouter.modifyPosition(keyWithHook, params, '');
    } catch (bytes memory reason) {
      assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
    }
  }

  function boundSwapConfig(SwapConfig memory swapConfig) internal view returns (SwapConfig memory) {
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    return boundSwapConfig(swapConfig, sqrtPriceX96);
  }

  function swapWithBothPools(
    SwapConfig memory swapConfig,
    bool needClaim,
    bool needExpectEmit,
    bool needExpectRevert
  ) internal returns (uint256 egAmount) {
    boundSwapConfig(swapConfig);

    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    BalanceDelta deltaWithoutHook;
    try swapRouter.swap(keyWithoutHook, params, testSettings, '') returns (BalanceDelta delta) {
      deltaWithoutHook = delta;
    } catch (bytes memory reason) {
      assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
      return 0;
    }

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

    bytes memory signature = getSignature(quoteSignerKey, getDigest(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    int256 maxAmountOut = amountIn * swapConfig.maxExchangeRate / swapConfig.exchangeRateDenom;
    egAmount =
      uint256(maxAmountOut < amountOutWithoutHook ? amountOutWithoutHook - maxAmountOut : int256(0));

    if (needExpectEmit) {
      vm.expectEmit(true, true, true, true, address(hook));
      emit IUnorderedNonce.UseNonce(swapConfig.nonce);
    }
    if (needExpectRevert) {
      vm.expectRevert(
        abi.encodeWithSelector(
          CustomRevert.WrappedError.selector,
          hook,
          ICLHooks.beforeSwap.selector,
          abi.encodeWithSelector(IUnorderedNonce.NonceAlreadyUsed.selector, swapConfig.nonce),
          abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        )
      );
    }

    BalanceDelta deltaWithHook = swapRouter.swap(keyWithHook, params, testSettings, hookData);
    int128 amountOutWithHook;
    if (swapConfig.zeroForOne) {
      amountOutWithHook = deltaWithHook.amount1();
    } else {
      amountOutWithHook = deltaWithHook.amount0();
    }

    if (needClaim) {
      vm.prank(operator);
      try hook.claimEGTokens(tokens, new uint256[](2)) {}
      catch (bytes memory reason) {
        assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
      }
    }
  }

  function swapWithHookOnly(SwapConfig memory swapConfig) internal {
    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    bytes memory signature = getSignature(quoteSignerKey, getDigest(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  function getDigest(SwapConfig memory swapConfig) internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        swapRouter,
        keyWithHook,
        swapConfig.zeroForOne,
        swapConfig.maxAmountIn,
        swapConfig.maxExchangeRate,
        swapConfig.exchangeRateDenom,
        swapConfig.nonce,
        swapConfig.expiryTime
      )
    );
  }

  function getHookData(SwapConfig memory swapConfig, bytes memory signature)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encode(
      swapConfig.maxAmountIn,
      swapConfig.maxExchangeRate,
      swapConfig.exchangeRateDenom,
      swapConfig.nonce,
      swapConfig.expiryTime,
      signature
    );
  }
}
