// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IELHook {
  /// @notice Thrown when the sender is not whitelisted
  error KSHookNotWhitelisted(address sender);

  /// @notice Thrown when the new surplus recipient is the zero address
  error KSHookInvalidSurplusRecipient();

  /// @notice Thrown when trying to swap in exact output mode
  error KSHookExactOutputDisabled();

  /// @notice Thrown when the signature is expired
  error KSHookExpiredSignature();

  /// @notice Thrown when the signature is invalid
  error KSHookInvalidSignature();

  /**
   * @notice Thrown when the input amount is not within the expected range
   * @param minAmountIn the minimum input amount
   * @param maxAmountIn the maximum input amount
   * @param amountIn the actual input amount
   */
  error KSHookInvalidAmountIn(int256 minAmountIn, int256 maxAmountIn, int256 amountIn);

  /// @notice Emitted when the amount out is not within the expected range
  event KSHookUpdateWhitelisted(address indexed sender, bool grantOrRevoke);

  /// @notice Emitted when the surplus recipient is updated
  event KSHookUpdateSurplusRecipient(address indexed surplusRecipient);

  /// @notice Emitted when a surplus amount of token is seized
  event KSHookSeizeSurplusToken(address indexed token, int256 amount);

  /// @notice Emitted when surplus tokens are claimed
  event KSHookClaimSurplusTokens(address[] tokens, uint256[] amounts);

  /// @notice Return the whitelist status of an address
  function whitelisted(address sender) external view returns (bool);

  /// @notice Return the address of the surplus recipient
  function surplusRecipient() external view returns (address);

  /**
   * @notice Update the whitelist status of an address
   * @param sender the address to update
   * @param grantOrRevoke the new whitelist status
   */
  function updateWhitelist(address sender, bool grantOrRevoke) external;

  /**
   * @notice Update the surplus recipient
   * @param recipient the new surplus recipient
   */
  function updateSurplusRecipient(address recipient) external;

  /**
   * @notice Claim surplus tokens accrued by the hook
   * @param tokens the addresses of the tokens to claim
   */
  function claimSurplusTokens(address[] calldata tokens) external;
}
