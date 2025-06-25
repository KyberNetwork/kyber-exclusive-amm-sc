// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CalldataDecoder} from 'uniswap/v4-periphery/src/libraries/CalldataDecoder.sol';

/**
 * @title HookDataDecoder
 * @notice Library for abi decoding hook data
 */
library HookDataDecoder {
  /// @dev equivalent to: abi.decode(hookData, (int256, int256, int256, uint256, uint256, bytes)) in calldata
  function decodeAllHookData(bytes calldata hookData)
    internal
    pure
    returns (
      int256 maxAmountIn,
      int256 maxExchangeRate,
      int256 exchangeRateDenom,
      uint256 nonce,
      uint256 expiryTime,
      bytes memory signature
    )
  {
    // no length check performed, as there is a length check in `toBytes`
    assembly ("memory-safe") {
      maxAmountIn := calldataload(hookData.offset)
      maxExchangeRate := calldataload(add(hookData.offset, 0x20))
      exchangeRateDenom := calldataload(add(hookData.offset, 0x40))
      nonce := calldataload(add(hookData.offset, 0x60))
      expiryTime := calldataload(add(hookData.offset, 0x80))
    }

    signature = CalldataDecoder.toBytes(hookData, 5);
  }

  /// @dev equivalent to: (, int256 maxExchangeRate, int256 exchangeRateDenom,,,) = abi.decode(hookData, (int256, int256, int256, uint256, uint256, bytes)) in calldata
  function decodeExchangeRate(bytes calldata hookData)
    internal
    pure
    returns (int256 maxExchangeRate, int256 exchangeRateDenom)
  {
    assembly ("memory-safe") {
      maxExchangeRate := calldataload(add(hookData.offset, 0x20))
      exchangeRateDenom := calldataload(add(hookData.offset, 0x40))
    }
  }
}
