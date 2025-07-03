// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract PancakeSwapHookPoolTest is PancakeSwapHookBaseTest {
  function test_fuzz_pancakeswap_multiple_actions(
    PoolConfig memory poolConfig,
    AddLiquidityConfig[NUM_POSITIONS_AND_SWAPS] memory addLiquidityConfigs,
    SwapConfig[NUM_POSITIONS_AND_SWAPS] memory swapConfigs,
    uint256[NUM_POSITIONS_AND_SWAPS * 3] memory actions
  ) public {
    initPools(poolConfig);
    actions = createFuzzyActionsOrdering(actions);
    ICLPoolManager.ModifyLiquidityParams[] memory paramsList =
      new ICLPoolManager.ModifyLiquidityParams[](NUM_POSITIONS_AND_SWAPS);

    for (uint256 i = 0; i < NUM_POSITIONS_AND_SWAPS * 3; i++) {
      if (actions[i] < NUM_POSITIONS_AND_SWAPS) {
        handleSwap(swapConfigs[actions[i]], actions[i], poolConfig.protocolEGFee);
      } else if (actions[i] < NUM_POSITIONS_AND_SWAPS * 2) {
        actions[i] -= NUM_POSITIONS_AND_SWAPS;
        paramsList[actions[i]] = addLiquidityBothPools(addLiquidityConfigs[actions[i]]);
      } else {
        actions[i] -= NUM_POSITIONS_AND_SWAPS * 2;
        removeLiquidityBothPools(paramsList[actions[i]]);
      }
    }

    vm.expectEmit(true, true, true, true, address(hook));
    emit IFFHookAdmin.ClaimProtocolEGs(egRecipient, tokens, protocolEGAmounts);
    vm.prank(operator);
    hook.claimProtocolEGs(tokens, new uint256[](2));

    if (totalEGAmounts[0] > 1000) {
      assertLe(
        vault.balanceOf(address(hook), currency0),
        totalEGAmounts[0] / 1000,
        'remaining EG on token 0 exceeds 0.1% of total EG'
      );
    }
    if (totalEGAmounts[1] > 1000) {
      assertLe(
        vault.balanceOf(address(hook), currency1),
        totalEGAmounts[1] / 1000,
        'remaining EG on token 1 exceeds 0.1% of total EG'
      );
    }
  }

  function handleSwap(SwapConfig memory swapConfig, uint256 action, uint256 protocolEGFee)
    internal
    returns (uint256 protocolEGAmount)
  {
    createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfig);
    swapConfig.nonce = action + 1;
    uint256 totalEGAmount = swapBothPools(swapConfig);
    protocolEGAmount = totalEGAmount * protocolEGFee / MathExt.PIPS_DENOMINATOR;

    totalEGAmounts[swapConfig.zeroForOne ? 1 : 0] += totalEGAmount;
    protocolEGAmounts[swapConfig.zeroForOne ? 1 : 0] += protocolEGAmount;
  }

  /// forge-config: default.fuzz.runs = 20
  function test_fuzz_pancakeswap_multiple_actions_pausedHook(
    PoolConfig memory poolConfig,
    AddLiquidityConfig[NUM_POSITIONS_AND_SWAPS] memory addLiquidityConfigs,
    SwapConfig[NUM_POSITIONS_AND_SWAPS] memory swapConfigs,
    uint256[NUM_POSITIONS_AND_SWAPS * 3] memory actions
  ) public {
    initPools(poolConfig);
    actions = createFuzzyActionsOrdering(actions);
    ICLPoolManager.ModifyLiquidityParams[] memory paramsList =
      new ICLPoolManager.ModifyLiquidityParams[](NUM_POSITIONS_AND_SWAPS);

    vm.prank(guardian);
    Management(address(hook)).pause();

    for (uint256 i = 0; i < NUM_POSITIONS_AND_SWAPS * 3; i++) {
      if (actions[i] < NUM_POSITIONS_AND_SWAPS) {
        SwapConfig memory swapConfig =
          createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfigs[actions[i]]);
        swapConfig.nonce = actions[i] + 1;
        swapBothPools_pausedHook(swapConfig);
      } else if (actions[i] < NUM_POSITIONS_AND_SWAPS * 2) {
        actions[i] -= NUM_POSITIONS_AND_SWAPS;
        paramsList[actions[i]] = addLiquidityBothPools_pausedHook(addLiquidityConfigs[actions[i]]);
      } else {
        actions[i] -= NUM_POSITIONS_AND_SWAPS * 2;
        removeLiquidityBothPools_pausedHook(paramsList[actions[i]]);
      }
    }
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_exactOut_fail(
    PoolConfig memory poolConfig,
    AddLiquidityConfig memory addLiquidityConfig,
    SwapConfig memory swapConfig
  ) public {
    initPools(poolConfig);
    addLiquidityOnlyHook(addLiquidityConfig);
    createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfig);
    swapConfig.amountSpecified = -swapConfig.amountSpecified;

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(IFFHookBeforeSwap.ExactOutDisabled.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapOnlyHook(swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_invalidSender_fail(
    uint256 actorIndex,
    PoolConfig memory poolConfig,
    AddLiquidityConfig memory addLiquidityConfig,
    SwapConfig memory swapConfig
  ) public {
    initPools(poolConfig);
    addLiquidityOnlyHook(addLiquidityConfig);
    createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfig);

    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    bytes memory signature = sign(quoteSignerKey, hash(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    CLPoolManagerRouter newRouter =
      CLPoolManagerRouter(actors[bound(actorIndex, 0, actors.length - 1)]);
    deployCodeTo('CLPoolManagerRouter.sol', abi.encode(vault, manager), address(newRouter));

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(IFFHookBeforeSwap.InvalidSignature.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    newRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_expiredSignature_fail(
    PoolConfig memory poolConfig,
    AddLiquidityConfig memory addLiquidityConfig,
    SwapConfig memory swapConfig
  ) public {
    initPools(poolConfig);
    addLiquidityOnlyHook(addLiquidityConfig);
    createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfig);

    vm.warp(swapConfig.expiryTime + bound(swapConfig.expiryTime, 1, 1e18));

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(
          IFFHookBeforeSwap.ExpiredSignature.selector, swapConfig.expiryTime, block.timestamp
        ),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapOnlyHook(swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_tooLargeAmountIn_fail(
    PoolConfig memory poolConfig,
    AddLiquidityConfig memory addLiquidityConfig,
    SwapConfig memory swapConfig
  ) public {
    initPools(poolConfig);
    addLiquidityOnlyHook(addLiquidityConfig);
    createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfig);
    swapConfig.amountSpecified =
      -bound(swapConfig.amountSpecified, swapConfig.maxAmountIn + 1, type(int256).max);

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(
          IFFHookBeforeSwap.TooLargeAmountIn.selector,
          swapConfig.maxAmountIn,
          -swapConfig.amountSpecified
        ),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapOnlyHook(swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_wrongSigner_fail(
    uint256 privKey,
    PoolConfig memory poolConfig,
    AddLiquidityConfig memory addLiquidityConfig,
    SwapConfig memory swapConfig
  ) public {
    initPools(poolConfig);
    addLiquidityOnlyHook(addLiquidityConfig);
    createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfig);

    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    privKey = bound(privKey, 1, SECP256K1_ORDER - 1);
    vm.assume(privKey != quoteSignerKey);

    bytes memory signature = sign(privKey, hash(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(IFFHookBeforeSwap.InvalidSignature.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_usedNonce_fail(
    PoolConfig memory poolConfig,
    AddLiquidityConfig memory addLiquidityConfig,
    SwapConfig memory swapConfig
  ) public {
    initPools(poolConfig);
    addLiquidityOnlyHook(addLiquidityConfig);
    createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfig);

    // swap twice with the same nonce
    swapOnlyHook(swapConfig);

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        ICLHooks.beforeSwap.selector,
        abi.encodeWithSelector(IFFHookNonces.NonceAlreadyUsed.selector, swapConfig.nonce),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapOnlyHook(swapConfig);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_zeroNonce(
    PoolConfig memory poolConfig,
    AddLiquidityConfig memory addLiquidityConfig,
    SwapConfig memory swapConfig1,
    SwapConfig memory swapConfig2
  ) public {
    initPools(poolConfig);
    addLiquidityOnlyHook(addLiquidityConfig);

    // swap twice with zero nonce
    createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfig1);
    swapConfig1.nonce = 0;
    swapOnlyHook(swapConfig1);

    createFuzzySwapConfig(PoolId.unwrap(idWithHook), swapConfig2);
    swapConfig2.nonce = 0;
    swapOnlyHook(swapConfig2);
  }
}
