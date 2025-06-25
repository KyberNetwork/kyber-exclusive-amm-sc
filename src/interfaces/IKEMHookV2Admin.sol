// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IKEMHookV2Admin
 * @notice Common admin functions for the KEMHookV2 contracts
 */
interface IKEMHookV2Admin {
  /**
   * @notice Update the quote signer
   * @notice Can only be called by the current admin
   * @param newSigner the address of the new quote signer
   */
  function updateQuoteSigner(address newSigner) external;

  /**
   * @notice Update the protocol's EG-recipient
   * @notice Can only be called by the current admin
   * @param newRecipient the address of the new EG-recipient
   */
  function updateEGRecipient(address newRecipient) external;

  /**
   * @notice Update the protocol's EG fee for a given pool
   * @notice Can only be called by the current admin
   * @param poolId the ID of the pool
   * @param newFee the new EG fee
   */
  function updateProtocolEGFee(bytes32 poolId, int256 newFee) external;

  /**
   * @notice Claim some of protocol's shares of EG
   * @notice Can only be called by the account with `CLAIM_ROLE`
   * @param tokens the addresses of the tokens to claim
   * @param amounts the amounts of the tokens to claim, set to 0 to claim all
   */
  function claimProtocolEG(address[] calldata tokens, uint256[] calldata amounts) external;
}
