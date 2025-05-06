// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICommon} from './ICommon.sol';

/**
 * @title IKEMHook
 * @notice Common interface for the KEMHook contracts
 */
interface IKEMHook is ICommon {
  /// @notice Thrown when trying to claim tokens by non-claimable account
  error NonClaimableAccount(address account);

  /// @notice Thrown when trying to swap in exact output mode
  error ExactOutputDisabled();

  /**
   * @notice Thrown when the signature is expired
   * @param expiryTime the expiry time
   * @param currentTime the current time
   */
  error ExpiredSignature(uint256 expiryTime, uint256 currentTime);

  /// @notice Thrown when the signature is invalid
  error InvalidSignature();

  /**
   * @notice Thrown when the input amount exceeds the maximum amount
   * @param maxAmountIn the maximum input amount
   * @param amountIn the actual input amount
   */
  error ExceededMaxAmountIn(int256 maxAmountIn, int256 amountIn);

  /// @notice Emitted when the claimable status of an account is updated
  event UpdateClaimable(address indexed account, bool status);

  /// @notice Emitted when the quote signer is updated
  event UpdateQuoteSigner(address indexed quoteSigner);

  /// @notice Emitted when the equilibrium-gain recipient is updated
  event UpdateEgRecipient(address indexed egRecipient);

  /// @notice Emitted when a equilibrium-gain token is absorbed
  event AbsorbEgToken(bytes32 indexed poolId, address indexed token, int256 amount);

  /// @notice Emitted when some of equilibrium-gain tokens are claimed
  event ClaimEgTokens(address indexed egRecipient, address[] tokens, uint256[] amounts);

  /// @notice Return the claimable status of an account
  function claimable(address) external view returns (bool);

  /// @notice Return the address responsible for signing the quote
  function quoteSigner() external view returns (address);

  /// @notice Return the address of the equilibrium-gain recipient
  function egRecipient() external view returns (address);

  /**
   * @notice Update the claimable status of some accounts
   * @notice Can only be called by the current owner
   * @param accounts the addresses of the accounts to update
   * @param newStatus the new status for the accounts
   */
  function updateClaimable(address[] calldata accounts, bool newStatus) external;

  /**
   * @notice Update the quote signer
   * @notice Can only be called by the current owner
   * @param newSigner the address of the new quote signer
   */
  function updateQuoteSigner(address newSigner) external;

  /**
   * @notice Update the equilibrium-gain recipient
   * @notice Can only be called by the current owner
   * @param newRecipient the address of the new equilibrium-gain recipient
   */
  function updateEgRecipient(address newRecipient) external;

  /**
   * @notice Claim some of equilibrium-gain tokens accrued by the hook
   * @notice Can only be called by the claimable accounts
   * @param tokens the addresses of the tokens to claim
   * @param amounts the amounts of the tokens to claim, set to 0 to claim all
   */
  function claimEgTokens(address[] calldata tokens, uint256[] calldata amounts) external;
}
