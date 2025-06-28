// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IFFHookBeforeSwap
/// @notice Interface for the FFHookBeforeSwap module
interface IFFHookBeforeSwap {
  /// @notice Thrown when exact output is disabled
  error ExactOutputDisabled();

  /// @notice Thrown when the fair exchange rate is too large
  error TooLargeFairExchangeRate(uint256 rate);

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
  error TooLargeAmountIn(int256 maxAmountIn, int256 amountIn);
}
