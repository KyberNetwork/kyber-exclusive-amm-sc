// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title FFHookAccounting
/// @notice Accounting module for the FFHook contract
abstract contract FFHookAccounting {
  /// @notice Moves some value to currency delta
  function _burn(address token, uint256 amount) internal virtual;

  /// @notice Moves some value from currency delta
  function _mint(address token, uint256 amount) internal virtual;

  /// @notice Nets out some value to the recipient
  function _take(address token, address recipient, uint256 amount) internal virtual;
}
