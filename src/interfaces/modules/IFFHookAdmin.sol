// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IFFHookAdmin
 * @notice Interface for FFHookAdmin module
 */
interface IFFHookAdmin {
  /// @notice Thrown when the protocol EG fee is set too large
  error TooLargeProtocolEGFee(uint24 fee);

  /// @notice Thrown when trying to unpause the hook
  error UnpauseDisabled();

  /// @notice Emitted when the quote signer is updated
  event UpdateQuoteSigner(address indexed oldSigner, address indexed newSigner);

  /// @notice Emitted when the protocol's EG-recipient is updated
  event UpdateEGRecipient(address indexed oldRecipient, address indexed newRecipient);

  /// @notice Emitted when the protocol's EG fee for a given pool is updated
  event UpdateProtocolEGFee(bytes32 indexed poolId, uint24 oldFee, uint24 newFee);

  /// @notice Emitted when some of protocol's shares of EG are claimed
  event ClaimProtocolEGs(address indexed egRecipient, address[] tokens, uint256[] amounts);

  /// @notice Emitted when some of EGs are rescued
  event RescueEGs(address indexed egRecipient, address[] tokens, uint256[] amounts);

  /**
   * @notice Called by the current admin to update the quote signer
   * @param newSigner the address of the new quote signer
   */
  function updateQuoteSigner(address newSigner) external;

  /**
   * @notice Called by the current admin to update the protocol's EG-recipient
   * @param newRecipient the address of the new EG-recipient
   */
  function updateEGRecipient(address newRecipient) external;

  /**
   * @notice Called by the current admin to update the protocol's EG fee for a given pool
   * @param poolId the ID of the pool
   * @param newFee the new EG fee
   */
  function updateProtocolEGFee(bytes32 poolId, uint24 newFee) external;

  /**
   * @notice Called by the operators to claim some of protocol's EG fees
   * @param tokens the addresses of the tokens to claim
   * @param amounts the amounts of the tokens to claim, set to 0 to claim all
   */
  function claimProtocolEGs(address[] memory tokens, uint256[] memory amounts) external;

  /**
   * @notice Called by the rescuers to rescue some of EGs
   * @notice Can only be called when the hook is paused
   * @param tokens the addresses of the tokens to rescue
   * @param amounts the amounts of the tokens to rescue, set to 0 to rescue all
   */
  function rescueEGs(address[] memory tokens, uint256[] memory amounts) external;
}
