// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title SafeTransientStorageAccess
/// @notice Contains functions for safely accessing transient storage
library SafeTransientStorageAccess {
  function tstore(bytes32 slot, bytes32 value) internal {
    assembly ("memory-safe") {
      tstore(slot, value)
    }
  }

  function tloadBytes32(bytes32 slot) internal returns (bytes32 value) {
    assembly ("memory-safe") {
      value := tload(slot)
      tstore(slot, 0)
    }
  }

  function tstore(bytes32 slot, uint256 value) internal {
    assembly ("memory-safe") {
      tstore(slot, value)
    }
  }

  function tloadUint256(bytes32 slot) internal returns (uint256 value) {
    assembly ("memory-safe") {
      value := tload(slot)
      tstore(slot, 0)
    }
  }

  function tloadUint128(bytes32 slot) internal returns (uint128 value) {
    assembly ("memory-safe") {
      value := tload(slot)
      tstore(slot, 0)
    }
  }
}
