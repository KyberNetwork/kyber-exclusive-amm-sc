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
  /// @return _maxAmountIn The maximum amount in
  /// @return _inverseFairExchangeRate The inverse fair exchange rate
  /// @return _nonce The nonce
  /// @return _expiryTime The expiry time
  /// @return _signature The signature
  function decodeHookData(bytes calldata hookData)
    internal
    pure
    returns (
      int256 _maxAmountIn,
      uint256 _inverseFairExchangeRate,
      uint256 _nonce,
      uint256 _expiryTime,
      bytes memory _signature
    )
  {
    // no length check performed, as there is a length check in `toBytes`
    assembly ("memory-safe") {
      _maxAmountIn := calldataload(hookData.offset)
      _inverseFairExchangeRate := calldataload(add(hookData.offset, 0x20))
      _nonce := calldataload(add(hookData.offset, 0x40))
      _expiryTime := calldataload(add(hookData.offset, 0x60))
    }

    _signature = CalldataDecoder.toBytes(hookData, 4);
  }

  /// @notice Decodes the fair exchange rate from the hook data
  /// @param hookData The hook data to decode
  /// @return _inverseFairExchangeRate The inverse fair exchange rate
  function inverseFairExchangeRate(bytes calldata hookData)
    internal
    pure
    returns (uint256 _inverseFairExchangeRate)
  {
    assembly ("memory-safe") {
      _inverseFairExchangeRate := calldataload(add(hookData.offset, 0x20))
    }
  }
}
