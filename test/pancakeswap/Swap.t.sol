// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract PancakeSwapHookSwapTest is PancakeSwapHookBaseTest {
  function test_pancakeswap_exactInput_succeed(SingleTestConfig memory config) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    config.swapConfig.nonce = bound(config.swapConfig.nonce, 1, type(uint256).max);

    uint256 egAmount = swapWithBothPools(config.swapConfig, false, true, false);

    Currency currencyOut = config.swapConfig.zeroForOne ? currency1 : currency0;
    assertEq(vault.balanceOf(address(hook), currencyOut), egAmount);

    tokens = newAddressesLength1(Currency.unwrap(currencyOut));
    vm.expectEmit(true, true, true, true, address(hook));
    emit IKEMHook.ClaimEGTokens(egRecipient, tokens, newUint256sLength1(uint256(egAmount)));
    vm.prank(operator);
    hook.claimEGTokens(tokens, newUint256sLength1(0));
  }

  function test_pancakeswap_exactInput_multiple_succeed(MultipleTestConfig memory config) public {
    initPools(config.poolConfig);

    config.needClaimFlags = bound(config.needClaimFlags, 0, (1 << MULTIPLE_TEST_CONFIG_LENGTH) - 1);

    for (uint256 i = 0; i < MULTIPLE_TEST_CONFIG_LENGTH; i++) {
      addLiquidity(config.addLiquidityAndSwapConfigs[i].addLiquidityConfig);
      config.addLiquidityAndSwapConfigs[i].swapConfig.nonce = i;
      swapWithBothPools(
        config.addLiquidityAndSwapConfigs[i].swapConfig,
        (config.needClaimFlags >> i & 1) == 1,
        false,
        false
      );
    }
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactInput_with_invalidSender_shouldFail(
    uint256 actorIndex,
    SingleTestConfig memory config
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    SwapConfig memory swapConfig = boundSwapConfig(config.swapConfig);

    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    bytes memory signature = getSignature(quoteSignerKey, getDigest(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    CLPoolManagerRouter newRouter =
      CLPoolManagerRouter(actors[bound(actorIndex, 0, actors.length - 1)]);
    deployCodeTo('CLPoolManagerRouter.sol', abi.encode(vault, manager), address(newRouter));

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(IKEMHook.InvalidSignature.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    newRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactOutput_shouldFail(SingleTestConfig memory config) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    SwapConfig memory swapConfig = boundSwapConfig(config.swapConfig);

    swapConfig.amountSpecified = -swapConfig.amountSpecified;

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(IKEMHook.ExactOutputDisabled.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactInput_with_expiredSignature_shouldFail(
    SingleTestConfig memory config
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    SwapConfig memory swapConfig = boundSwapConfig(config.swapConfig);

    vm.warp(swapConfig.expiryTime + bound(swapConfig.expiryTime, 1, 1e18));

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(
          IKEMHook.ExpiredSignature.selector, swapConfig.expiryTime, block.timestamp
        ),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactInput_with_exceededAmountIn_shouldFail(
    SingleTestConfig memory config
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    SwapConfig memory swapConfig = boundSwapConfig(config.swapConfig);

    swapConfig.amountSpecified =
      -bound(swapConfig.amountSpecified, swapConfig.maxAmountIn + 1, type(int256).max);

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(
          IKEMHook.ExceededMaxAmountIn.selector, swapConfig.maxAmountIn, -swapConfig.amountSpecified
        ),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapWithHookOnly(swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactInput_with_invalidSignature_shouldFail(
    uint256 privKey,
    SingleTestConfig memory config
  ) public {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    SwapConfig memory swapConfig = boundSwapConfig(config.swapConfig);

    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    privKey = bound(privKey, 1, SECP256K1_ORDER - 1);
    vm.assume(privKey != quoteSignerKey);

    bytes memory signature = getSignature(privKey, getDigest(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

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

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactInput_with_usedNonce_shouldFail(SingleTestConfig memory config)
    public
  {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    config.swapConfig.nonce = bound(config.swapConfig.nonce, 1, type(uint256).max);

    swapWithBothPools(config.swapConfig, false, false, false);

    swapWithBothPools(config.swapConfig, false, false, true);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactInput_with_zeroNonce_succeed(SingleTestConfig memory config)
    public
  {
    initPools(config.poolConfig);
    addLiquidity(config.addLiquidityConfig);
    config.swapConfig.nonce = 0;

    swapWithBothPools(config.swapConfig, false, false, false);

    swapWithBothPools(config.swapConfig, false, false, false);
  }
}
