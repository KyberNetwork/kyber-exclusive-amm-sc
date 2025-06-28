// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CalldataDecoder} from 'uniswap/v4-periphery/src/libraries/CalldataDecoder.sol';

/**
 * @title CalldataDecoderExt
 * @notice Contains functions for decoding hook data
 */
library CalldataDecoderExt {
  /// @notice Decodes the hook data into its components
  /// @param hookData The hook data to decode
  /// @return maxAmountIn The maximum amount in
  /// @return _fairExchangeRate The fair exchange rate
  /// @return nonce The nonce
  /// @return expiryTime The expiry time
  /// @return signature The signature
  function decodeHookData(bytes calldata hookData)
    internal
    pure
    returns (
      int256 maxAmountIn,
      uint256 _fairExchangeRate,
      uint256 nonce,
      uint256 expiryTime,
      bytes memory signature
    )
  {
    // no length check performed, as there is a length check in `toBytes`
    assembly ("memory-safe") {
      maxAmountIn := calldataload(hookData.offset)
      _fairExchangeRate := calldataload(add(hookData.offset, 0x20))
      nonce := calldataload(add(hookData.offset, 0x40))
      expiryTime := calldataload(add(hookData.offset, 0x60))
    }

    signature = CalldataDecoder.toBytes(hookData, 4);
  }

  /// @notice Decodes the fair exchange rate from the hook data
  /// @param hookData The hook data to decode
  /// @return _fairExchangeRate The fair exchange rate
  function fairExchangeRate(bytes calldata hookData)
    internal
    pure
    returns (uint256 _fairExchangeRate)
  {
    assembly ("memory-safe") {
      _fairExchangeRate := calldataload(add(hookData.offset, 0x20))
    }
  }
}
