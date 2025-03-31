// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IKEMHook
 * @notice Common interface for the KEMHook contracts
 */
interface IKEMHook {
  /// @notice Thrown when the sender is not whitelisted
  error NotWhitelisted(address sender);

  /// @notice Thrown when the new address to be updated is the zero address
  error InvalidAddress();

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

  /// @notice Thrown when the lengths of the arrays are mismatched
  error MismatchedArrayLengths();

  /// @notice Emitted when the whitelist status of an address is updated
  event WhitelistSender(address indexed sender, bool grantOrRevoke);

  /// @notice Emitted when the signer is updated
  event UpdateQuoteSigner(address indexed quoteSigner);

  /// @notice Emitted when the surplus recipient is updated
  event UpdateSurplusRecipient(address indexed surplusRecipient);

  /// @notice Emitted when a surplus amount of token is taken
  event TakeSurplusToken(bytes32 indexed poolId, address indexed token, int256 amount);

  /// @notice Emitted when surplus tokens are claimed
  event ClaimSurplusTokens(address indexed surplusRecipient, address[] tokens, uint256[] amounts);

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
