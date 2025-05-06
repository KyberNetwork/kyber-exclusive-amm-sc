// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IUnorderedNonce
 * @notice Interface for the UnorderedNonce contract
 */
interface IUnorderedNonce {
  /// @notice Thrown when a nonce has already been used
  error NonceAlreadyUsed(uint256 nonce);

  /// @notice Emitted when a nonce is consumed
  event UseNonce(uint256 nonce);

  /// @notice mapping of nonces consumed by each address, where a nonce is a single bit on the 256-bit bitmap
  /// @dev word is at most type(uint248).max
  function nonces(uint256 word) external view returns (uint256 bitmap);
}
