// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ICommon
/// @notice Common interface for all contracts
interface ICommon {
  /// @notice Thrown when trying to update with zero address
  error InvalidAddress();

  /// @notice Thrown when the lengths of the arrays are mismatched
  error MismatchedArrayLengths();
}
