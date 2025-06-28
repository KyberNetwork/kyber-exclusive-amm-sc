// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IFFHookStateView
 * @notice Interface for FFHookStateView module
 */
interface IFFHookStateView {
  /// @notice Returns the address responsible for signing the quote
  function quoteSigner() external view returns (address);

  /// @notice Returns the address of the equilibrium-gain recipient
  function egRecipient() external view returns (address);

  /// @notice Returns the unclaimed protocol EG amount of a given token
  function protocolEGUnclaimed(address token) external view returns (uint256);
}
