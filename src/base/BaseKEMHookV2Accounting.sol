// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract BaseKEMHookV2Accounting {

  /// @notice Nets out some value to the recipient
  function _take(address token, address recipient, uint256 amount) internal virtual;

  /// @notice Pays on behalf of the recipient
  function _settle(address token, address recipient, uint256 amount) internal virtual;
}
