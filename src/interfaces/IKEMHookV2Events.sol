// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IKEMHookV2Events
 * @notice Common events for the KEMHookV2 contracts
 */
interface IKEMHookV2Events {
  /// @notice Emitted when the quote signer is updated
  event UpdateQuoteSigner(address indexed oldSigner, address indexed newSigner);

  /// @notice Emitted when the protocol's EG-recipient is updated
  event UpdateEGRecipient(address indexed oldRecipient, address indexed newRecipient);

  /// @notice Emitted when the protocol's EG fee for a given pool is updated
  event UpdateProtocolEGFee(bytes32 indexed poolId, uint24 oldFee, uint24 newFee);

  /// @notice Emitted when an eg-token is absorbed
  event AbsorbEG(bytes32 indexed poolId, address indexed token, uint256 amount);

  /// @notice Emitted when some of protocol's shares of EG are claimed
  event ClaimProtocolEG(address indexed egRecipient, address[] tokens, uint256[] amounts);

  /// @notice Emitted when a position's shares of EG are claimed
  event ClaimPositionEG(uint256 indexed tokenId, uint256 egAmount0, uint256 egAmount1);
}
