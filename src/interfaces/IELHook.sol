// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolId} from 'uniswap/v4-core/src/types/PoolId.sol';

interface IELHook {
  /// @notice Thrown when the sender is not whitelisted
  error ELHookNotWhitelisted(address sender);

  /// @notice Thrown when the new address to be updated is the zero address
  error ELHookInvalidAddress();

  /// @notice Thrown when trying to swap in exact output mode
  error ELHookExactOutputDisabled();

  /**
   * @notice Thrown when the signature is expired
   * @param expiryTime the expiry time
   * @param currentTime the current time
   */
  error ELHookExpiredSignature(uint256 expiryTime, uint256 currentTime);

  /// @notice Thrown when the signature is invalid
  error ELHookInvalidSignature();

  /**
   * @notice Thrown when the input amount is exceeded the maximum amount
   * @param maxAmountIn the maximum input amount
   * @param amountIn the actual input amount
   */
  error ELHookExceededMaxAmountIn(int256 maxAmountIn, int256 amountIn);

  /// @notice Thrown when the lengths of the arrays are mismatched
  error ELHookMismatchedArrayLengths();

  /// @notice Emitted when the whitelist status of an address is updated
  event ELHookWhitelistSender(address indexed sender, bool grantOrRevoke);

  /// @notice Emitted when the signer is updated
  event ELHookUpdateQuoteSigner(address indexed quoteSigner);

  /// @notice Emitted when the surplus recipient is updated
  event ELHookUpdateSurplusRecipient(address indexed surplusRecipient);

  /// @notice Emitted when a surplus amount of token is seized
  event ELHookSeizeSurplusToken(PoolId indexed poolId, address indexed token, int256 amount);

  /// @notice Emitted when surplus tokens are claimed
  event ELHookClaimSurplusTokens(
    address indexed surplusRecipient, address[] tokens, uint256[] amounts
  );

  /// @notice Return the whitelist status of an address
  function whitelisted(address sender) external view returns (bool);

  /// @notice Return the address of the signer responsible for signing the quote
  function quoteSigner() external view returns (address);

  /// @notice Return the address of the surplus recipient
  function surplusRecipient() external view returns (address);

  /**
   * @notice Update the whitelist status of an address
   * @param senders the addresses to update
   * @param grantOrRevoke the new whitelist status
   */
  function whitelistSenders(address[] calldata senders, bool grantOrRevoke) external;

  /**
   * @notice Update the quote signer
   * @param newSigner the new signer
   */
  function updateQuoteSigner(address newSigner) external;

  /**
   * @notice Update the surplus recipient
   * @param newRecipient the new surplus recipient
   */
  function updateSurplusRecipient(address newRecipient) external;

  /**
   * @notice Claim surplus tokens accrued by the hook
   * @param tokens the addresses of the tokens to claim
   * @param amounts the amounts of the tokens to claim, set to 0 to claim all
   */
  function claimSurplusTokens(address[] calldata tokens, uint256[] calldata amounts) external;
}
