// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

abstract contract BaseTest is Test {
  address owner;
  address operator;
  address quoteSigner;
  uint256 quoteSignerKey;
  address surplusRecipient;
  address[] actorAddresses;

  function setUp() public virtual {
    owner = makeAddr('owner');
    operator = makeAddr('operator');
    (quoteSigner, quoteSignerKey) = makeAddrAndKey('quoteSigner');
    surplusRecipient = makeAddr('surplusRecipient');
    actorAddresses = [owner, operator, quoteSigner, surplusRecipient, makeAddr('anyone')];
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
        ? bound(sqrtPriceLimitX96, getMinPriceLimit(), getSqrtPrice1_1() - 100)
        : bound(sqrtPriceLimitX96, getSqrtPrice1_1() + 100, getMaxPriceLimit())
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
    return (exceeded && border != type(int256).max) || border == 0
      ? bound(exchangeRateDenom, border + 1, type(int256).max)
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

  function getMinPriceLimit() internal view virtual returns (uint160);

  function getMaxPriceLimit() internal view virtual returns (uint160);

  function getSqrtPrice1_1() internal view virtual returns (uint160);
}
