// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IKEMHookV2State
 * @notice Common state getters for the KEMHookV2 contracts
 */
interface IKEMHookV2State {
  enum ClaimType {
    ProtocolEG,
    PositionEG
  }

  /// @notice Return the role for the claimants
  function CLAIM_ROLE() external view returns (bytes32);

  /// @notice Return the address responsible for signing the quote
  function quoteSigner() external view returns (address);

  /// @notice Return the address of the equilibrium-gain recipient
  function egRecipient() external view returns (address);

  /// @notice Return the protocol EG fee of a given pool
  function protocolEGFeeOf(bytes32 poolId) external view returns (int256);

  /// @notice Return the protocol EG amount of a given token
  function protocolEGAmountOf(address token) external view returns (uint256);
}
