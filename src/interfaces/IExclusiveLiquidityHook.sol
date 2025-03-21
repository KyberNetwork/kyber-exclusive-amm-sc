// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExclusiveLiquidityHook {
  event UpdateRouter(address router, bool grantOrRevoke);

  error KSHookNotRouter(address sender);

  error InvalidSurplusRecipient();

  error KSHookExactOutputDisabled();

  error KSHookExpiredSignature();

  error KSHookInvalidSignature();

  error ExceededMaxAmountIn();

  /**
   * @notice Claim surplus tokens accrued by the hook
   * @param ids the addresses of the tokens to claim, padded with 0s: `uint256(uint160(token))`
   */
  function claimSurplusTokens(uint256[] calldata ids) external;
}
