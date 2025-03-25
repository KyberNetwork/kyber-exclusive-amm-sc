// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'src/UniswapV4ELHook.sol';

import 'uniswap/v4-core/src/libraries/SafeCast.sol';
import 'uniswap/v4-core/test/utils/Deployers.sol';
import 'uniswap/v4-periphery/src/utils/HookMiner.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

contract UniswapV4ELHookTest is Deployers {
  using SafeCast for *;

  address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

  address owner;
  address operator;
  address signer;
  uint256 signerKey;
  address surplusRecipient;
  address account;
  uint256 accountKey;

  address hook;
  PoolKey keyWithoutHook;
  PoolKey keyWithHook;

  PoolSwapTest.TestSettings testSettings =
    PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

  function setUp() public {
    owner = makeAddr('owner');
    operator = makeAddr('operator');
    (signer, signerKey) = makeAddrAndKey('signer');
    surplusRecipient = makeAddr('surplusRecipient');
    (account, accountKey) = makeAddrAndKey('account');

    initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    keyWithoutHook = key;

    hook = address(
      uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)
    );
    deployCodeTo(
      'UniswapV4ELHook.sol',
      abi.encode(manager, owner, newAddressesLength1(operator), signer, surplusRecipient),
      hook
    );

    (keyWithHook,) =
      initPoolAndAddLiquidity(currency0, currency1, IHooks(hook), 3000, SQRT_PRICE_1_1);

    vm.prank(owner);
    IELHook(hook).whitelistSenders(newAddressesLength1(address(swapRouter)), true);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_updateWhitelist(address sender, bool grantOrRevoke) public {
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookWhitelistSender(sender, grantOrRevoke);
    IELHook(hook).whitelistSenders(newAddressesLength1(sender), grantOrRevoke);
    assertEq(IELHook(hook).whitelisted(sender), grantOrRevoke);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_updateSigner(address newSigner) public {
    vm.assume(newSigner != address(0));
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookUpdateSigner(newSigner);
    IELHook(hook).updateSigner(newSigner);
    assertEq(IELHook(hook).signer(), newSigner);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_updateSurplusRecipient(address recipient) public {
    vm.assume(recipient != address(0));
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookUpdateSurplusRecipient(recipient);
    IELHook(hook).updateSurplusRecipient(recipient);
    assertEq(IELHook(hook).surplusRecipient(), recipient);
  }

  function test_updateSigner_with_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IELHook.ELHookInvalidAddress.selector);
    IELHook(hook).updateSigner(address(0));
  }

  function test_updateSurplusRecipient_with_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IELHook.ELHookInvalidAddress.selector);
    IELHook(hook).updateSurplusRecipient(address(0));
  }

  function test_claimSurplusTokens(
    uint256 mintAmount0,
    uint256 mintAmount1,
    uint256 claimAmount0,
    uint256 claimAmount1
  ) public {
    mintAmount0 = bound(mintAmount0, 0, uint128(type(int128).max));
    mintAmount1 = bound(mintAmount1, 0, uint128(type(int128).max));
    claimAmount0 = bound(claimAmount0, 0, mintAmount0);
    claimAmount1 = bound(claimAmount1, 0, mintAmount1);
    manager.unlock(abi.encode(mintAmount0, mintAmount1));

    address[] memory tokens = new address[](2);
    tokens[0] = Currency.unwrap(currency0);
    tokens[1] = Currency.unwrap(currency1);
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = claimAmount0 == 0 ? mintAmount0 : claimAmount0;
    amounts[1] = claimAmount1 == 0 ? mintAmount1 : claimAmount1;

    vm.prank(operator);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookClaimSurplusTokens(tokens, amounts);
    amounts[0] = claimAmount0;
    amounts[1] = claimAmount1;
    IELHook(hook).claimSurplusTokens(tokens, amounts);
  }

  function unlockCallback(bytes calldata data) public returns (bytes memory) {
    (uint256 mintAmount0, uint256 mintAmount1) = abi.decode(data, (uint256, uint256));
    manager.mint(hook, uint256(uint160(Currency.unwrap(currency0))), mintAmount0);
    manager.mint(hook, uint256(uint160(Currency.unwrap(currency1))), mintAmount1);

    manager.sync(currency0);
    IERC20(Currency.unwrap(currency0)).transfer(address(manager), mintAmount0);
    manager.settle();

    manager.sync(currency1);
    IERC20(Currency.unwrap(currency1)).transfer(address(manager), mintAmount1);
    manager.settle();
  }

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

      emit IELHook.ELHookSeizeSurplusToken(
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

    address[] memory tokens = newAddressesLength1(Currency.unwrap(currencyOut));
    uint256[] memory amounts = newUint256sLength1(uint256(surplusAmount));
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookClaimSurplusTokens(tokens, amounts);
    vm.prank(operator);
    IELHook(hook).claimSurplusTokens(tokens, newUint256sLength1(0));
  }

  /// forge-config: default.fuzz.runs = 5
  function test_swap_exactInput_not_whitelistRouter_shouldFail(
    PoolSwapTest router,
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96
  ) public {
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

  function normalizeTestInput(
    int256 amountSpecified,
    bool zeroForOne,
    uint160 sqrtPriceLimitX96,
    int256 maxAmountIn,
    int256 maxExchangeRate,
    uint256 expiryTime
  ) public view returns (int256, bool, uint160, int256, int256, uint256) {
    amountSpecified = int256(bound(amountSpecified, -3e11, -1e3));
    sqrtPriceLimitX96 = uint160(
      zeroForOne
        ? bound(sqrtPriceLimitX96, MIN_PRICE_LIMIT, SQRT_PRICE_1_1 - 100)
        : bound(sqrtPriceLimitX96, SQRT_PRICE_1_1 + 100, MAX_PRICE_LIMIT)
    );
    maxAmountIn = bound(maxAmountIn, -amountSpecified, type(int256).max - 1);
    maxExchangeRate = bound(maxExchangeRate, 0, type(int256).max / -amountSpecified);
    expiryTime = bound(expiryTime, block.timestamp, block.timestamp + 1e6);

    return
      (amountSpecified, zeroForOne, sqrtPriceLimitX96, maxAmountIn, maxExchangeRate, expiryTime);
  }

  function getExchangeRateDenom(
    int256 amountIn,
    int256 maxExchangeRate,
    int256 amountOutWithoutHook,
    int256 exchangeRateDenom,
    bool exceeded
  ) internal pure returns (int256) {
    int256 border = amountOutWithoutHook > 0
      ? amountIn * maxExchangeRate / amountOutWithoutHook
      : type(int256).max;
    return exceeded || border == 0
      ? bound(exchangeRateDenom, border, type(int256).max)
      : bound(exchangeRateDenom, 1, border);
  }

  function getSignature(uint256 privKey, bytes32 digest)
    internal
    pure
    returns (bytes memory signature)
  {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
    signature = abi.encodePacked(r, s, v);
  }

  function newAddressesLength1(address addr) internal pure returns (address[] memory addresses) {
    addresses = new address[](1);
    addresses[0] = addr;
  }

  function newUint256sLength1(uint256 value) internal pure returns (uint256[] memory values) {
    values = new uint256[](1);
    values[0] = value;
  }
}
