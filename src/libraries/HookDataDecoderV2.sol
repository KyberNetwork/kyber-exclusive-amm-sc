// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CalldataDecoder} from 'uniswap/v4-periphery/src/libraries/CalldataDecoder.sol';

/**
 * @title HookDataDecoderV2
 * @notice Library for abi decoding hook data (v2)
 */
library HookDataDecoderV2 {
  /// @dev equivalent to: abi.decode(hookData, (int256, int256, uint256, uint256, bytes)) in calldata
  function decodeAllHookData(bytes calldata hookData)
    internal
    pure
    returns (
      int256 maxAmountIn,
      int256 maxExchangeRate,
      uint256 nonce,
      uint256 expiryTime,
      bytes memory signature
    )
  {
    // no length check performed, as there is a length check in `toBytes`
    assembly ("memory-safe") {
      maxAmountIn := calldataload(hookData.offset)
      maxExchangeRate := calldataload(add(hookData.offset, 0x20))
      nonce := calldataload(add(hookData.offset, 0x40))
      expiryTime := calldataload(add(hookData.offset, 0x60))
    }

    signature = CalldataDecoder.toBytes(hookData, 4);
  }

  /// @dev equivalent to: (, int256 maxExchangeRate,,,) = abi.decode(hookData, (int256, int256, uint256, uint256, bytes)) in calldata
  function decodeMaxExchangeRate(bytes calldata hookData)
    internal
    pure
    returns (int256 maxExchangeRate)
  {
    assembly ("memory-safe") {
      maxExchangeRate := calldataload(add(hookData.offset, 0x20))
    }
  }
}
