// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract PancakeSwapHookSwapTest is PancakeSwapHookBaseTest {
  function test_pancakeswap_exactInput_succeed(SingleTestConfig memory config) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);

    uint256 egAmount = swapWithBothPools(config.swapConfig, false);

    Currency currencyOut = config.swapConfig.zeroForOne ? currency1 : currency0;
    assertEq(vault.balanceOf(address(hook), currencyOut), egAmount);

    tokens = newAddressesLength1(Currency.unwrap(currencyOut));
    vm.expectEmit(true, true, true, true, address(hook));
    emit IKEMHook.ClaimEgTokens(egRecipient, tokens, newUint256sLength1(uint256(egAmount)));
    vm.prank(operator);
    hook.claimEgTokens(tokens, newUint256sLength1(0));
  }

  function test_pancakeswap_exactInput_multiple_succeed(MultipleTestConfig memory config) public {
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
  function test_pancakeswap_exactInput_not_whitelistSender_shouldFail(
    uint256 actorIndex,
    SingleTestConfig memory config
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    CLPoolManagerRouter newRouter =
      CLPoolManagerRouter(actors[bound(actorIndex, 0, actors.length - 1)]);
    vm.assume(newRouter != swapRouter);
    swapRouter = newRouter;
    deployCodeTo('CLPoolManagerRouter.sol', abi.encode(vault, manager), address(swapRouter));

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(IKEMHook.NonWhitelistedAccount.selector, swapRouter),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(config.swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactOutput_shouldFail(SingleTestConfig memory config) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    config.swapConfig.amountSpecified = -config.swapConfig.amountSpecified;

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(IKEMHook.ExactOutputDisabled.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(config.swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactInput_with_expiredSignature_shouldFail(
    SingleTestConfig memory config
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    vm.warp(config.swapConfig.expiryTime + bound(config.swapConfig.expiryTime, 1, 1e18));

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(
          IKEMHook.ExpiredSignature.selector, config.swapConfig.expiryTime, block.timestamp
        ),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(config.swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactInput_with_exceededAmountIn_shouldFail(
    SingleTestConfig memory config
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    config.swapConfig.amountSpecified =
      -bound(config.swapConfig.amountSpecified, config.swapConfig.maxAmountIn + 1, type(int256).max);

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
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
  function test_pancakeswap_exactInput_with_invalidSignature_shouldFail(
    SingleTestConfig memory config,
    uint256 privKey
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    boundSwapConfig(config.swapConfig);

    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
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
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(IKEMHook.InvalidSignature.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }
}
