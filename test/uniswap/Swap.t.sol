// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract UniswapHookSwapTest is UniswapHookBaseTest {
  function test_uniswap_exactInput_succeed(SingleTestConfig memory config) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);

    uint256 egAmount = swapWithBothPools(config.swapConfig, false);

    Currency currencyOut = config.swapConfig.zeroForOne ? currency1 : currency0;
    assertEq(manager.balanceOf(address(hook), currencyOut.toId()), egAmount);

    tokens = newAddressesLength1(Currency.unwrap(currencyOut));
    vm.expectEmit(true, true, true, true, address(hook));
    emit IKEMHook.ClaimEgTokens(egRecipient, tokens, newUint256sLength1(uint256(egAmount)));
    vm.prank(operator);
    hook.claimEgTokens(tokens, newUint256sLength1(0));
  }

  function test_uniswap_exactInput_multiple_succeed(MultipleTestConfig memory config) public {
    initPools(config.poolConfig);

    for (uint256 i = 0; i < config.addLiquidityAndSwapConfigs.length; i++) {
      if (i == 20) break;
      addLiquidity(config.addLiquidityAndSwapConfigs[i].addLiquidityConfig);
      swapWithBothPools(
        config.addLiquidityAndSwapConfigs[i].swapConfig, (config.needClaimFlags >> i & 1) == 1
      );
    }
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_exactInput_not_whitelistSender_shouldFail(
    uint256 actorIndex,
    SingleTestConfig memory config
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    PoolSwapTest newRouter = PoolSwapTest(actors[bound(actorIndex, 0, actors.length - 1)]);
    vm.assume(newRouter != swapRouter);
    swapRouter = newRouter;
    deployCodeTo('PoolSwapTest.sol', abi.encode(manager), address(swapRouter));

    bytes memory signature = getSignature(
      quoteSignerKey,
      keccak256(
        abi.encode(
          swapRouter,
          keyWithHook,
          zeroForOne,
          maxAmountIn,
          maxExchangeRate,
          exchangeRateDenom,
          expiryTime
        )
      )
    );
    bytes memory hookData =
      abi.encode(maxAmountIn, maxExchangeRate, exchangeRateDenom, expiryTime, signature);

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(IKEMHook.NonWhitelistedAccount.selector, swapRouter),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(config.swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_exactOutput_shouldFail(SingleTestConfig memory config) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    config.swapConfig.amountSpecified = -config.swapConfig.amountSpecified;

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(IKEMHook.ExactOutputDisabled.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(config.swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_exactInput_with_expiredSignature_shouldFail(SingleTestConfig memory config)
    public
  {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    vm.warp(config.swapConfig.expiryTime + bound(config.swapConfig.expiryTime, 1, 1e18));

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(
          IKEMHook.ExpiredSignature.selector, config.swapConfig.expiryTime, block.timestamp
        ),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(config.swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_exactInput_with_exceededAmountIn_shouldFail(SingleTestConfig memory config)
    public
  {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    config.swapConfig.amountSpecified =
      -bound(config.swapConfig.amountSpecified, config.swapConfig.maxAmountIn + 1, type(int256).max);

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(
          IKEMHook.ExceededMaxAmountIn.selector,
          config.swapConfig.maxAmountIn,
          -config.swapConfig.amountSpecified
        ),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(config.swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_exactInput_with_invalidSignature_shouldFail(
    SingleTestConfig memory config,
    uint256 privKey
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      zeroForOne: config.swapConfig.zeroForOne,
      amountSpecified: config.swapConfig.amountSpecified,
      sqrtPriceLimitX96: config.swapConfig.sqrtPriceLimitX96
    });

    privKey = bound(privKey, 1, SECP256K1_ORDER - 1);
    vm.assume(privKey != quoteSignerKey);

    bytes memory signature = getSignature(
      privKey,
      keccak256(
        abi.encode(
          keyWithHook,
          config.swapConfig.zeroForOne,
          config.swapConfig.maxAmountIn,
          config.swapConfig.maxExchangeRate,
          config.swapConfig.exchangeRateDenom,
          config.swapConfig.expiryTime
        )
      )
    );
    bytes memory hookData = abi.encode(
      config.swapConfig.maxAmountIn,
      config.swapConfig.maxExchangeRate,
      config.swapConfig.exchangeRateDenom,
      config.swapConfig.expiryTime,
      signature
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(IKEMHook.InvalidSignature.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }
}
