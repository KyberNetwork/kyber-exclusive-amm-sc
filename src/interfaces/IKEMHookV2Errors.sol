// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IKEMHookV2Errors
 * @notice Common errors for the KEMHookV2 contracts
 */
interface IKEMHookV2Errors {
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


}
