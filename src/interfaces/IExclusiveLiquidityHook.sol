// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExclusiveLiquidityHook {
  error KSHookNotWhitelisted(address sender);

  error KSHookInvalidSurplusRecipient();

  error KSHookExactOutputDisabled();

  error KSHookExpiredSignature();

  error KSHookInvalidSignature();

  error KSHookInvalidAmountIn(int128 minAmountIn, int128 maxAmountIn, int128 amountIn);

  event KSHookUpdateWhitelisted(address indexed sender, bool grantOrRevoke);

  event KSHookUpdateSurplusRecipient(address indexed surplusRecipient);

  /**
   * @notice Update the whitelist status of an address
   * @param sender the address to update
   * @param grantOrRevoke the new whitelist status
   */
  function updateWhitelist(address sender, bool grantOrRevoke) external;

  /**
   * @notice Claim surplus tokens accrued by the hook
   * @param ids the addresses of the tokens to claim, padded with 0s: `uint256(uint160(token))`
   */
  function claimSurplusTokens(uint256[] calldata ids) external;
}
