// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.t.sol';

import 'src/UniswapV4KEMHook.sol';
import 'src/base/BaseKEMHook.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import 'uniswap/v4-core/src/libraries/CustomRevert.sol';

import 'uniswap/v4-core/src/test/Fuzzers.sol';

import 'uniswap/v4-core/src/types/PoolKey.sol';
import 'uniswap/v4-core/test/utils/Deployers.sol';

contract UniswapHookBaseTest is BaseTest, Deployers, Fuzzers {
  using StateLibrary for IPoolManager;

  PoolKey keyWithoutHook;
  PoolId idWithoutHook;
  PoolKey keyWithHook;

  PoolSwapTest.TestSettings testSettings =
    PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

  address[] tokens;

  function setUp() public override {
    super.setUp();
    
    deployFreshManagerAndRouters();
    deployMintAndApprove2Currencies();
    deployFreshHook();

    tokens = new address[](2);
    tokens[0] = Currency.unwrap(currency0);
    tokens[1] = Currency.unwrap(currency1);
  }

  function deployFreshHook() internal {
    hook = IKEMHook(
      address(
        uint160(
          Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        )
      )
    );
    deployCodeTo(
      'UniswapV4KEMHook.sol',
      abi.encode(
        manager,
        owner,
        newAddressesLength1(operator),
        newAddressesLength1(address(swapRouter)),
        quoteSigner,
        egRecipient
      ),
      address(hook)
    );
  }

  function initPools(PoolConfig memory poolConfig) internal {
    poolConfig.fee = boundFee(poolConfig.fee);
    poolConfig.tickSpacing = boundTickSpacing(poolConfig.tickSpacing);
    poolConfig.sqrtPriceX96 =
      createRandomSqrtPriceX96(poolConfig.tickSpacing, poolConfig.sqrtPriceX96seed);

    keyWithoutHook =
      PoolKey(currency0, currency1, poolConfig.fee, poolConfig.tickSpacing, IHooks(address(0)));
    idWithoutHook = keyWithoutHook.toId();
    keyWithHook =
      PoolKey(currency0, currency1, poolConfig.fee, poolConfig.tickSpacing, IHooks(address(hook)));

    manager.initialize(keyWithoutHook, poolConfig.sqrtPriceX96);
    manager.initialize(keyWithHook, poolConfig.sqrtPriceX96);
  }

  function addLiquidity(PositionConfig memory positionConfig) internal {
    IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
      tickLower: positionConfig.lowerTick,
      tickUpper: positionConfig.upperTick,
      liquidityDelta: positionConfig.liquidityDelta,
      salt: 0
    });
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    params = createFuzzyLiquidityParamsWithTightBound(keyWithoutHook, params, sqrtPriceX96, 20);

    modifyLiquidityRouter.modifyLiquidity(keyWithoutHook, params, '');
    modifyLiquidityRouter.modifyLiquidity(keyWithHook, params, '');
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

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
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
        manager.balanceOf(address(hook), uint256(uint160(Currency.unwrap(currencyOut)))),
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
    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
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
