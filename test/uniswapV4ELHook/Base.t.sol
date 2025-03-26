// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'src/UniswapV4ELHook.sol';

import 'uniswap/v4-core/src/libraries/SafeCast.sol';
import 'uniswap/v4-core/test/utils/Deployers.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

contract UniswapV4ELHookBaseTest is Deployers {
  using SafeCast for *;

  address owner;
  address operator;
  address signer;
  uint256 signerKey;
  address surplusRecipient;

  address[] actorAddresses;

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

    actorAddresses = [owner, operator, signer, surplusRecipient, makeAddr('anyone')];

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
