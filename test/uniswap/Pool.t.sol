// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract UniswapHookPoolTest is UniswapHookBaseTest {
  function test_fuzz_uniswap_multiple_actions(
    PoolConfig memory poolConfig,
    AddLiquidityConfig[NUM_POSITIONS_AND_SWAPS] memory addLiquidityConfigs,
    SwapConfig[NUM_POSITIONS_AND_SWAPS] memory swapConfigs,
    uint256[NUM_POSITIONS_AND_SWAPS * 3] memory actions
  ) public {
    initPools(poolConfig);

    ModifyLiquidityParams[] memory paramsList = new ModifyLiquidityParams[](NUM_POSITIONS_AND_SWAPS);

    actions = createFuzzyActionsOrdering(actions);

    for (uint256 i = 0; i < NUM_POSITIONS_AND_SWAPS * 3; i++) {
      if (actions[i] < NUM_POSITIONS_AND_SWAPS) {
        handleSwap(swapConfigs[actions[i]], actions[i], poolConfig.protocolEGFee);
      } else if (actions[i] < NUM_POSITIONS_AND_SWAPS * 2) {
        actions[i] -= NUM_POSITIONS_AND_SWAPS;
        paramsList[actions[i]] = addLiquidityBothPools(addLiquidityConfigs[actions[i]]);
      } else {
        actions[i] -= NUM_POSITIONS_AND_SWAPS * 2;
        handleRemoveLiquidity(paramsList[actions[i]]);
      }
    }

    vm.expectEmit(true, true, true, true, address(hook));
    emit IFFHookAdmin.ClaimProtocolEGs(egRecipient, tokens, protocolEGAmounts);
    vm.prank(operator);
    hook.claimProtocolEGs(tokens, new uint256[](2));

    if (totalEGAmounts[0] > 1000) {
      assertLe(
        manager.balanceOf(address(hook), uint160(tokens[0])),
        totalEGAmounts[0] / 1000,
        'remaining EG on token 0 exceeds 0.1% of total EG'
      );
    }
    if (totalEGAmounts[1] > 1000) {
      assertLe(
        manager.balanceOf(address(hook), uint160(tokens[1])),
        totalEGAmounts[1] / 1000,
        'remaining EG on token 1 exceeds 0.1% of total EG'
      );
    }
  }

  function handleSwap(SwapConfig memory swapConfig, uint256 action, uint256 protocolEGFee)
    internal
    returns (uint256 protocolEGAmount)
  {
    createFuzzySwapConfig(PoolId.unwrap(idWithoutHook), swapConfig);
    swapConfig.nonce = action + 1;
    uint256 totalEGAmount = swapBothPools(swapConfig, true, false);
    protocolEGAmount = totalEGAmount * protocolEGFee / MathExt.PIPS_DENOMINATOR;

    totalEGAmounts[swapConfig.zeroForOne ? 1 : 0] += totalEGAmount;
    protocolEGAmounts[swapConfig.zeroForOne ? 1 : 0] += protocolEGAmount;
  }

  function handleRemoveLiquidity(ModifyLiquidityParams memory params) internal {
    // flip the sign to remove the position
    params.liquidityDelta = -params.liquidityDelta;
    if (params.liquidityDelta != 0) {
      modifyLiquidityNoChecks.modifyLiquidity(keyWithoutHook, params, '');
      modifyLiquidityNoChecks.modifyLiquidity(keyWithHook, params, '');
    }
  }

  // /// forge-config: default.fuzz.runs = 20
  // function test_fuzz_uniswap_multiple_addLiquidity_and_swap_pausedHook_succeed(
  //   PoolConfig memory poolConfig,
  //   AddLiquidityConfig[NUM_POSITIONS_AND_SWAPS] memory addLiquidityConfigs,
  //   SwapConfig[NUM_POSITIONS_AND_SWAPS] memory swapConfigs
  // ) public {
  //   initPools(poolConfig);

  //   vm.prank(guardian);
  //   Management(address(hook)).pause();

  //   for (uint256 i = 0; i < NUM_POSITIONS_AND_SWAPS; i++) {
  //     AddLiquidityConfig memory addLiquidityConfig = addLiquidityConfigs[i];
  //     SwapConfig memory swapConfig = swapConfigs[i];

  //     addLiquidityBothPools(addLiquidityConfig);
  //     createFuzzySwapConfig(PoolId.unwrap(idWithoutHook), swapConfig);
  //     swapConfig.nonce = i + 1;

  //     swapBothPools_pausedHook(swapConfig);
  //   }
  // }

  // function test_uniswap_exactInput_multiple_succeed(MultipleTestConfig memory config) public {
  //   initPools(config.poolConfig);

  //   config.needClaimFlags = bound(config.needClaimFlags, 0, (1 << MULTIPLE_TEST_CONFIG_LENGTH) - 1);

  //   for (uint256 i = 0; i < MULTIPLE_TEST_CONFIG_LENGTH; i++) {
  //     addLiquidityBothPools(config.addLiquidityAndSwapConfigs[i].addLiquidityConfig);
  //     config.addLiquidityAndSwapConfigs[i].swapConfig.nonce = i;
  //     swapBothPools(
  //       config.addLiquidityAndSwapConfigs[i].swapConfig,
  //       (config.needClaimFlags >> i & 1) == 1,
  //       false,
  //       false
  //     );
  //   }
  // }

  // /// forge-config: default.fuzz.runs = 20
  // function test_uniswap_exactInput_with_invalidSender_shouldFail(
  //   uint256 actorIndex,
  //   SingleTestConfig memory config
  // ) public {
  //   initPools(config.poolConfig);
  //   addLiquidityBothPools(config.addLiquidityConfig);
  //   SwapConfig memory swapConfig = createFuzzySwapConfig(config.swapConfig);

  //   IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
  //     zeroForOne: swapConfig.zeroForOne,
  //     amountSpecified: swapConfig.amountSpecified,
  //     sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
  //   });

  //   bytes memory signature = getSignature(quoteSignerKey, getDigest(swapConfig));
  //   bytes memory hookData = getHookData(swapConfig, signature);

  //   PoolSwapTest newRouter = PoolSwapTest(actors[bound(actorIndex, 0, actors.length - 1)]);
  //   deployCodeTo('PoolSwapTest.sol', abi.encode(manager), address(newRouter));

  //   vm.expectRevert(
  //     abi.encodeWithSelector(
  //       CustomRevert.WrappedError.selector,
  //       hook,
  //       IHooks.beforeSwap.selector,
  //       abi.encodeWithSelector(IKEMHook.InvalidSignature.selector),
  //       abi.encodeWithSelector(Hooks.HookCallFailed.selector)
  //     )
  //   );
  //   newRouter.swap(keyWithHook, params, testSettings, hookData);
  // }

  // /// forge-config: default.fuzz.runs = 20
  // function test_uniswap_exactOutput_shouldFail(SingleTestConfig memory config) public {
  //   initPools(config.poolConfig);
  //   addLiquidityBothPools(config.addLiquidityConfig);
  //   SwapConfig memory swapConfig = createFuzzySwapConfig(config.swapConfig);

  //   swapConfig.amountSpecified = -swapConfig.amountSpecified;

  //   vm.expectRevert(
  //     abi.encodeWithSelector(
  //       CustomRevert.WrappedError.selector,
  //       hook,
  //       IHooks.beforeSwap.selector,
  //       abi.encodeWithSelector(IKEMHook.ExactOutputDisabled.selector),
  //       abi.encodeWithSelector(Hooks.HookCallFailed.selector)
  //     )
  //   );
  //   swapWithHookOnly(swapConfig);
  // }

  // /// forge-config: default.fuzz.runs = 20
  // function test_uniswap_exactInput_with_expiredSignature_shouldFail(SingleTestConfig memory config)
  //   public
  // {
  //   initPools(config.poolConfig);
  //   addLiquidityBothPools(config.addLiquidityConfig);
  //   SwapConfig memory swapConfig = createFuzzySwapConfig(config.swapConfig);

  //   vm.warp(swapConfig.expiryTime + bound(swapConfig.expiryTime, 1, 1e18));

  //   vm.expectRevert(
  //     abi.encodeWithSelector(
  //       CustomRevert.WrappedError.selector,
  //       hook,
  //       IHooks.beforeSwap.selector,
  //       abi.encodeWithSelector(
  //         IKEMHook.ExpiredSignature.selector, swapConfig.expiryTime, block.timestamp
  //       ),
  //       abi.encodeWithSelector(Hooks.HookCallFailed.selector)
  //     )
  //   );
  //   swapWithHookOnly(swapConfig);
  // }

  // /// forge-config: default.fuzz.runs = 20
  // function test_uniswap_exactInput_with_exceededAmountIn_shouldFail(SingleTestConfig memory config)
  //   public
  // {
  //   initPools(config.poolConfig);
  //   addLiquidityBothPools(config.addLiquidityConfig);
  //   SwapConfig memory swapConfig = createFuzzySwapConfig(config.swapConfig);

  //   swapConfig.amountSpecified =
  //     -bound(swapConfig.amountSpecified, swapConfig.maxAmountIn + 1, type(int256).max);

  //   vm.expectRevert(
  //     abi.encodeWithSelector(
  //       CustomRevert.WrappedError.selector,
  //       hook,
  //       IHooks.beforeSwap.selector,
  //       abi.encodeWithSelector(
  //         IKEMHook.ExceededMaxAmountIn.selector, swapConfig.maxAmountIn, -swapConfig.amountSpecified
  //       ),
  //       abi.encodeWithSelector(Hooks.HookCallFailed.selector)
  //     )
  //   );
  //   swapWithHookOnly(swapConfig);
  // }

  // /// forge-config: default.fuzz.runs = 20
  // function test_uniswap_exactInput_with_invalidSignature_shouldFail(
  //   uint256 privKey,
  //   SingleTestConfig memory config
  // ) public {
  //   initPools(config.poolConfig);
  //   addLiquidityBothPools(config.addLiquidityConfig);
  //   SwapConfig memory swapConfig = createFuzzySwapConfig(config.swapConfig);

  //   IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
  //     zeroForOne: swapConfig.zeroForOne,
  //     amountSpecified: swapConfig.amountSpecified,
  //     sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
  //   });

  //   privKey = bound(privKey, 1, SECP256K1_ORDER - 1);
  //   vm.assume(privKey != quoteSignerKey);

  //   bytes memory signature = getSignature(privKey, getDigest(swapConfig));
  //   bytes memory hookData = getHookData(swapConfig, signature);

  //   vm.expectRevert(
  //     abi.encodeWithSelector(
  //       CustomRevert.WrappedError.selector,
  //       hook,
  //       IHooks.beforeSwap.selector,
  //       abi.encodeWithSelector(IKEMHook.InvalidSignature.selector),
  //       abi.encodeWithSelector(Hooks.HookCallFailed.selector)
  //     )
  //   );
  //   swapRouter.swap(keyWithHook, params, testSettings, hookData);
  // }

  // /// forge-config: default.fuzz.runs = 20
  // function test_uniswap_exactInput_with_usedNonce_shouldFail(SingleTestConfig memory config) public {
  //   initPools(config.poolConfig);
  //   addLiquidityBothPools(config.addLiquidityConfig);
  //   config.swapConfig.nonce = bound(config.swapConfig.nonce, 1, type(uint256).max);

  //   swapBothPools(config.swapConfig, false, false, false);

  //   swapBothPools(config.swapConfig, false, false, true);
  // }

  // /// forge-config: default.fuzz.runs = 20
  // function test_uniswap_exactInput_with_zeroNonce_succeed(SingleTestConfig memory config) public {
  //   initPools(config.poolConfig);
  //   addLiquidityBothPools(config.addLiquidityConfig);
  //   config.swapConfig.nonce = 0;

  //   swapBothPools(config.swapConfig, false, false, false);

  //   swapBothPools(config.swapConfig, false, false, false);
  // }
}
