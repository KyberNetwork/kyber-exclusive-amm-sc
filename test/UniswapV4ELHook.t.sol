// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'src/UniswapV4ELHook.sol';

import 'uniswap/v4-core/src/libraries/SafeCast.sol';
import 'uniswap/v4-core/test/utils/Deployers.sol';
import 'uniswap/v4-periphery/src/utils/HookMiner.sol';

contract UniswapV4ELHookTest is Deployers {
  using SafeCast for *;

  address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

  address owner;
  uint256 ownerKey;
  address operator;
  uint256 operatorKey;
  address guardian;
  address surplusRecipient;
  address account;
  uint256 accountKey;

  address hook;
  PoolKey keyWithoutHook;
  PoolKey keyWithHook;

  PoolSwapTest.TestSettings testSettings =
    PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

  function setUp() public {
    (owner, ownerKey) = makeAddrAndKey('owner');
    (operator, operatorKey) = makeAddrAndKey('operator');
    guardian = makeAddr('guardian');
    surplusRecipient = makeAddr('surplusRecipient');
    (account, accountKey) = makeAddrAndKey('account');

    initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    keyWithoutHook = key;

    address[] memory initialOperators = new address[](1);
    initialOperators[0] = operator;
    address[] memory initialGuardians = new address[](1);
    initialGuardians[0] = guardian;
    hook = address(
      uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)
    );
    deployCodeTo(
      'UniswapV4ELHook.sol',
      abi.encode(manager, owner, initialOperators, initialGuardians, surplusRecipient),
      hook
    );

    (keyWithHook,) =
      initPoolAndAddLiquidity(currency0, currency1, IHooks(hook), 3000, SQRT_PRICE_1_1);

    vm.prank(owner);
    IELHook(hook).updateWhitelist(address(swapRouter), true);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_updateWhitelist(address sender, bool grantOrRevoke) public {
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.KSHookUpdateWhitelisted(sender, grantOrRevoke);
    IELHook(hook).updateWhitelist(sender, grantOrRevoke);
    assertEq(IELHook(hook).whitelisted(sender), grantOrRevoke);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_updateSurplusRecipient(address recipient) public {
    vm.assume(recipient != address(0));
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.KSHookUpdateSurplusRecipient(recipient);
    IELHook(hook).updateSurplusRecipient(recipient);
    assertEq(IELHook(hook).surplusRecipient(), recipient);
  }

  function test_updateSurplusRecipient_with_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IELHook.KSHookInvalidSurplusRecipient.selector);
    IELHook(hook).updateSurplusRecipient(address(0));
  }

  function test_swap_exactInput_and_claimSurplusTokens(
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 minAmountIn,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    uint32 log2ExchangeRateDenom,
    uint64 expiryTime
  ) public {
    (
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    ) = normalizeTestInput(
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    );

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    bytes memory signature = getSignature(
      operatorKey,
      keccak256(
        abi.encode(
          keyWithHook,
          zeroForOne,
          minAmountIn,
          maxAmountIn,
          maxExchangeRate,
          log2ExchangeRateDenom,
          expiryTime
        )
      )
    );

    bytes memory hookData = abi.encode(
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime,
      operator,
      signature
    );

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

    Currency currencyOut = zeroForOne ? currency1 : currency0;
    int256 maxAmountOut = (amountIn * maxExchangeRate) >> log2ExchangeRateDenom;
    int256 surplusAmount =
      maxAmountOut < amountOutWithoutHook ? amountOutWithoutHook - maxAmountOut : int256(0);
    if (surplusAmount > 0) {
      vm.expectEmit(true, true, true, true, hook);

      emit IELHook.KSHookSeizeSurplusToken(
        Currency.unwrap(currencyOut), amountOutWithoutHook - maxAmountOut
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

    address[] memory tokens = new address[](1);
    tokens[0] = Currency.unwrap(currencyOut);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = uint256(surplusAmount);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.KSHookClaimSurplusTokens(tokens, amounts);
    vm.prank(operator);
    IELHook(hook).claimSurplusTokens(tokens);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_swap_exactInput_not_whitelistRouter_shouldFail(
    PoolSwapTest router,
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 minAmountIn,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    uint32 log2ExchangeRateDenom,
    uint64 expiryTime
  ) public {
    vm.assume(router != swapRouter);
    deployCodeTo('PoolSwapTest.sol', abi.encode(manager), address(router));

    (
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    ) = normalizeTestInput(
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    );

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
        abi.encodeWithSelector(IELHook.KSHookNotWhitelisted.selector, address(router)),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    router.swap(keyWithHook, params, testSettings, '');
  }

  /// forge-config: default.fuzz.runs = 20
  function test_swap_exactOutput_shouldFail(
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 minAmountIn,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    uint32 log2ExchangeRateDenom,
    uint64 expiryTime
  ) public {
    (
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    ) = normalizeTestInput(
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    );
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
        abi.encodeWithSelector(IELHook.KSHookExactOutputDisabled.selector),
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
    int256 minAmountIn,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    uint32 log2ExchangeRateDenom,
    uint64 expiryTime
  ) public {
    (
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    ) = normalizeTestInput(
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    );

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    bytes memory hookData = abi.encode(
      minAmountIn, maxAmountIn, maxExchangeRate, log2ExchangeRateDenom, expiryTime, operator, ''
    );

    vm.warp(expiryTime + bound(expiryTime, 1, 1e9));
    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(IELHook.KSHookExpiredSignature.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_swap_exactInput_with_invalidOperator_shouldFail(
    address signer,
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 minAmountIn,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    uint32 log2ExchangeRateDenom,
    uint64 expiryTime
  ) public {
    vm.assume(signer != operator);

    (
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    ) = normalizeTestInput(
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    );

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    bytes memory hookData = abi.encode(
      minAmountIn, maxAmountIn, maxExchangeRate, log2ExchangeRateDenom, expiryTime, signer, ''
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(KyberSwapRole.KSRoleNotOperator.selector, signer),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_swap_exactInput_with_invalidAmountIn_shouldFail(
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 minAmountIn,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    uint32 log2ExchangeRateDenom,
    uint64 expiryTime
  ) public {
    (
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    ) = normalizeTestInput(
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    );
    if (amountSpecified % 2 == 0) {
      amountSpecified = -bound(amountSpecified, 1, minAmountIn - 1);
    } else {
      amountSpecified = -bound(amountSpecified, maxAmountIn + 1, type(int256).max);
    }

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    bytes memory hookData = abi.encode(
      minAmountIn, maxAmountIn, maxExchangeRate, log2ExchangeRateDenom, expiryTime, operator, ''
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(
          IELHook.KSHookInvalidAmountIn.selector, minAmountIn, maxAmountIn, -amountSpecified
        ),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_swap_exactInput_with_invalidSignature_shouldFail(
    uint256 signerKey,
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 minAmountIn,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    uint32 log2ExchangeRateDenom,
    uint64 expiryTime
  ) public {
    signerKey = bound(signerKey, 1, SECP256K1_ORDER - 1);
    vm.assume(signerKey != operatorKey);

    (
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    ) = normalizeTestInput(
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    );

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      amountSpecified: amountSpecified,
      zeroForOne: zeroForOne,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    bytes memory signature = getSignature(
      signerKey,
      keccak256(
        abi.encode(
          keyWithHook,
          zeroForOne,
          minAmountIn,
          maxAmountIn,
          maxExchangeRate,
          log2ExchangeRateDenom,
          expiryTime
        )
      )
    );

    bytes memory hookData = abi.encode(
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime,
      operator,
      signature
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        CustomRevert.WrappedError.selector,
        hook,
        IHooks.beforeSwap.selector,
        abi.encodeWithSelector(IELHook.KSHookInvalidSignature.selector),
        abi.encodeWithSelector(Hooks.HookCallFailed.selector)
      )
    );
    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  function normalizeTestInput(
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 minAmountIn,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    uint32 log2ExchangeRateDenom,
    uint64 expiryTime
  ) public view returns (int256, bool, uint160, int256, int256, int256, uint32, uint64) {
    amountSpecified = int256(bound(amountSpecified, -3e11, -1e3));
    sqrtPriceLimitX96 = uint160(
      zeroForOne
        ? bound(sqrtPriceLimitX96, MIN_PRICE_LIMIT, SQRT_PRICE_1_1 - 100)
        : bound(sqrtPriceLimitX96, SQRT_PRICE_1_1 + 100, MAX_PRICE_LIMIT)
    );
    minAmountIn = bound(minAmountIn, 2, -amountSpecified);
    maxAmountIn = bound(maxAmountIn, -amountSpecified, type(int256).max - 1);
    maxExchangeRate = bound(maxExchangeRate, 0, type(int256).max / -amountSpecified);
    log2ExchangeRateDenom = uint32(bound(log2ExchangeRateDenom, 0, 256));
    expiryTime = uint64(bound(expiryTime, block.timestamp, block.timestamp + 1e6));

    return (
      amountSpecified,
      zeroForOne,
      sqrtPriceLimitX96,
      minAmountIn,
      maxAmountIn,
      maxExchangeRate,
      log2ExchangeRateDenom,
      expiryTime
    );
  }

  function getSignature(uint256 privKey, bytes32 digest)
    internal
    pure
    returns (bytes memory signature)
  {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
    signature = abi.encodePacked(r, s, v);
  }
}
