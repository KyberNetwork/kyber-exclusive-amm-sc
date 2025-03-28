// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'src/UniswapV4ELHook.sol';

import 'uniswap/v4-core/src/libraries/SafeCast.sol';
import 'uniswap/v4-core/test/utils/Deployers.sol';

import {UniswapV4ELHookBaseTest} from 'test/uniswapV4ELHook/Base.t.sol';

contract UniswapV4ELHookSwapTest is UniswapV4ELHookBaseTest {
  function test_swap_exactInput_succeed(
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    int256 exchangeRateDenom,
    uint256 expiryTime
  ) public {
    (amountSpecified, zeroForOne, sqrtPriceLimitX96, maxAmountIn, maxExchangeRate, expiryTime) =
    normalizeTestInput(
      amountSpecified, zeroForOne, sqrtPriceLimitX96, maxAmountIn, maxExchangeRate, expiryTime
    );

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    BalanceDelta deltaWithoutHook = swapRouter.swap(keyWithoutHook, params, testSettings, '');
    int128 amountIn;
    int128 amountOutWithoutHook;
    if (zeroForOne) {
      amountIn = -deltaWithoutHook.amount0();
      amountOutWithoutHook = deltaWithoutHook.amount1();
    } else {
      amountIn = -deltaWithoutHook.amount1();
      amountOutWithoutHook = deltaWithoutHook.amount0();
    }

    exchangeRateDenom = getExchangeRateDenom(
      amountIn, maxExchangeRate, amountOutWithoutHook, exchangeRateDenom, expiryTime % 2 == 0
    );

    bytes memory signature = getSignature(
      signerKey,
      keccak256(
        abi.encode(
          keyWithHook, zeroForOne, maxAmountIn, maxExchangeRate, exchangeRateDenom, expiryTime
        )
      )
    );
    bytes memory hookData =
      abi.encode(maxAmountIn, maxExchangeRate, exchangeRateDenom, expiryTime, signature);

    Currency currencyOut = zeroForOne ? currency1 : currency0;
    int256 maxAmountOut = amountIn * maxExchangeRate / exchangeRateDenom;
    int256 surplusAmount =
      maxAmountOut < amountOutWithoutHook ? amountOutWithoutHook - maxAmountOut : int256(0);
    if (surplusAmount > 0) {
      vm.expectEmit(true, true, true, true, hook);

      emit IELHook.ELHookTakeSurplusToken(
        keyWithHook.toId(), Currency.unwrap(currencyOut), amountOutWithoutHook - maxAmountOut
      );
    }

    BalanceDelta deltaWithHook = swapRouter.swap(keyWithHook, params, testSettings, hookData);
    int128 amountOutWithHook;
    if (zeroForOne) {
      amountOutWithHook = deltaWithHook.amount1();
    } else {
      amountOutWithHook = deltaWithHook.amount0();
    }

    if (surplusAmount > 0) {
      assertEq(amountOutWithHook, maxAmountOut);
      assertEq(
        manager.balanceOf(hook, uint256(uint160(Currency.unwrap(currencyOut)))),
        uint256(int256(amountOutWithoutHook - maxAmountOut))
      );
    } else {
      assertEq(amountOutWithHook, amountOutWithoutHook);
    }

    address[] memory tokens = newAddressesLength1(Currency.unwrap(currencyOut));
    uint256[] memory amounts = newUint256sLength1(uint256(surplusAmount));
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookClaimSurplusTokens(surplusRecipient, tokens, amounts);
    vm.prank(operator);
    IELHook(hook).claimSurplusTokens(tokens, newUint256sLength1(0));
  }

  /// forge-config: default.fuzz.runs = 5
  function test_swap_exactInput_not_whitelistSender_shouldFail(
    uint256 addressIndex,
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96
  ) public {
    PoolSwapTest router =
      PoolSwapTest(actorAddresses[bound(addressIndex, 0, actorAddresses.length - 1)]);
    vm.assume(router != swapRouter);
    deployCodeTo('PoolSwapTest.sol', abi.encode(manager), address(router));

    (amountSpecified, zeroForOne, sqrtPriceLimitX96,,,) =
      normalizeTestInput(amountSpecified, zeroForOne, sqrtPriceLimitX96, 0, 0, 0);

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(IELHook.ELHookNotWhitelisted.selector, address(router)),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    router.swap(keyWithHook, params, testSettings, '');
  }

  /// forge-config: default.fuzz.runs = 20
  function test_swap_exactOutput_shouldFail(
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96
  ) public {
    (amountSpecified, zeroForOne, sqrtPriceLimitX96,,,) =
      normalizeTestInput(amountSpecified, zeroForOne, sqrtPriceLimitX96, 0, 0, 0);
    amountSpecified = -amountSpecified;

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(IELHook.ELHookExactOutputDisabled.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, '');
  }

  /// forge-config: default.fuzz.runs = 20
  function test_swap_exactInput_with_expiredSignature_shouldFail(
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    int256 exchangeRateDenom,
    uint256 expiryTime
  ) public {
    (amountSpecified, zeroForOne, sqrtPriceLimitX96, maxAmountIn, maxExchangeRate, expiryTime) =
    normalizeTestInput(
      amountSpecified, zeroForOne, sqrtPriceLimitX96, maxAmountIn, maxExchangeRate, expiryTime
    );

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    bytes memory hookData =
      abi.encode(maxAmountIn, maxExchangeRate, exchangeRateDenom, expiryTime, '');

    vm.warp(expiryTime + bound(expiryTime, 1, 1e9));
    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(IELHook.ELHookExpiredSignature.selector, expiryTime, block.timestamp),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_swap_exactInput_with_exceededAmountIn_shouldFail(
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    int256 exchangeRateDenom,
    uint256 expiryTime
  ) public {
    (amountSpecified, zeroForOne, sqrtPriceLimitX96, maxAmountIn, maxExchangeRate, expiryTime) =
    normalizeTestInput(
      amountSpecified, zeroForOne, sqrtPriceLimitX96, maxAmountIn, maxExchangeRate, expiryTime
    );
    amountSpecified = -bound(amountSpecified, maxAmountIn + 1, type(int256).max);

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    bytes memory hookData =
      abi.encode(maxAmountIn, maxExchangeRate, exchangeRateDenom, expiryTime, '');

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(
          IELHook.ELHookExceededMaxAmountIn.selector, maxAmountIn, -amountSpecified
        ),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_swap_exactInput_with_invalidSignature_shouldFail(
    uint256 privKey,
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    int256 exchangeRateDenom,
    uint256 expiryTime
  ) public {
    privKey = bound(privKey, 1, SECP256K1_ORDER - 1);
    vm.assume(privKey != signerKey);
    (amountSpecified, zeroForOne, sqrtPriceLimitX96, maxAmountIn, maxExchangeRate, expiryTime) =
    normalizeTestInput(
      amountSpecified, zeroForOne, sqrtPriceLimitX96, maxAmountIn, maxExchangeRate, expiryTime
    );

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    bytes memory signature = getSignature(
      privKey,
      keccak256(
        abi.encode(
          keyWithHook, zeroForOne, maxAmountIn, maxExchangeRate, exchangeRateDenom, expiryTime
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
        abi.encodeWithSelector(IELHook.ELHookInvalidSignature.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }
}
