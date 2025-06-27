// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CalldataDecoder} from 'uniswap/v4-periphery/src/libraries/CalldataDecoder.sol';

/**
 * @title KEMHookV2DataDecoder
 * @notice Library for abi decoding KEM Hook V2 data
 */
library KEMHookV2DataDecoder {
  /// @dev equivalent to: abi.decode(hookData, (int256, uint256, uint256, uint256, bytes)) in calldata
  function decodeAllHookData(bytes calldata hookData)
    internal
    pure
    returns (
      int256 maxAmountIn,
      uint256 fairExchangeRate,
      uint256 nonce,
      uint256 expiryTime,
      bytes memory signature
    )
  {
    // no length check performed, as there is a length check in `toBytes`
    assembly ("memory-safe") {
      maxAmountIn := calldataload(hookData.offset)
      fairExchangeRate := calldataload(add(hookData.offset, 0x20))
      nonce := calldataload(add(hookData.offset, 0x40))
      expiryTime := calldataload(add(hookData.offset, 0x60))
    }

    signature = CalldataDecoder.toBytes(hookData, 4);
  }

  /// @dev equivalent to: (, uint256 fairExchangeRate,,,) = abi.decode(hookData, (int256, uint256, uint256, uint256, bytes)) in calldata
  function decodeFairExchangeRate(bytes calldata hookData)
    internal
    pure
    returns (uint256 fairExchangeRate)
  {
    assembly ("memory-safe") {
      fairExchangeRate := calldataload(add(hookData.offset, 0x20))
    }
  }
}
