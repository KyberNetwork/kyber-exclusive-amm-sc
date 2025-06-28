// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFFHookStateView} from '../interfaces/modules/IFFHookStateView.sol';

import {PoolExt} from '../libraries/PoolExt.sol';

/// @title FFHookStorage
/// @notice Storage layout for the FFHook module
abstract contract FFHookStorage is IFFHookStateView {
  /// @inheritdoc IFFHookStateView
  address public quoteSigner;

  /// @inheritdoc IFFHookStateView
  address public egRecipient;

  /// @inheritdoc IFFHookStateView
  mapping(address => uint256) public protocolEGUnclaimed;

  /// @notice The state for each pool
  mapping(bytes32 poolId => PoolExt.State) internal pools;
}
