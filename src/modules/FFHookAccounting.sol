// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title FFHookAccounting
/// @notice Accounting module for the FFHook contract
abstract contract FFHookAccounting {
  /// @notice Call lock on the Vault or unlock on the PoolManager
  function _lockOrUnlock(bytes memory data) internal virtual;

  /// @notice Moves some value to currency delta
  function _burn(address token, uint256 amount) internal virtual;

  /// @notice Moves some value from currency delta
  function _mint(address token, uint256 amount) internal virtual;

  /// @notice Nets out some value to the recipient
  function _take(address token, address recipient, uint256 amount) internal virtual;

  /// @notice Get the total amount of unclaimed EGs for a given token
  function _getTotalEGUnclaimed(address token) internal view virtual returns (uint256);

  /// @notice Burn and take EGs to the EG recipient
  function _burnAndTakeEGs(bytes calldata data, address recipient) internal {
    (address[] memory tokens, uint256[] memory amounts) = abi.decode(data, (address[], uint256[]));

    for (uint256 i = 0; i < tokens.length; i++) {
      address token = tokens[i];
      uint256 amount = amounts[i];

      if (amount > 0) {
        _burn(token, amount);
        _take(token, recipient, amount);
      }
    }
  }
}
