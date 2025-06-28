// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IFFHookAfterSwap
/// @notice Interface for the FFHookAfterSwap module
interface IFFHookAfterSwap {
  /// @notice Emitted when an EG-token is absorbed
  event AbsorbEG(bytes32 indexed poolId, address indexed token, uint256 amount);
}
