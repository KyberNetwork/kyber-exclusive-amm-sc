// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKEMHook} from '../interfaces/IKEMHook.sol';
import {Rescuable} from './Rescuable.sol';

import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';

/**
 * @title BaseKEMHook
 * @notice Abstract contract containing common implementation for KEMHook contracts
 */
abstract contract BaseKEMHook is IKEMHook, Rescuable, Ownable {
  /// @inheritdoc IKEMHook
  mapping(address account => bool status) public claimable;

  /// @inheritdoc IKEMHook
  mapping(address account => bool status) public whitelisted;

  /// @inheritdoc IKEMHook
  address public quoteSigner;

  /// @inheritdoc IKEMHook
  address public egRecipient;

  constructor(
    address initialOwner,
    address[] memory initialClaimableAccounts,
    address[] memory initialWhitelistedAccounts,
    address initialQuoteSigner,
    address initialEgRecipient
  ) Ownable(initialOwner) {
    _updateClaimable(initialClaimableAccounts, true);
    _updateWhitelisted(initialWhitelistedAccounts, true);
    _updateQuoteSigner(initialQuoteSigner);
    _updateEgRecipient(initialEgRecipient);
  }

  /// @inheritdoc IKEMHook
  function updateClaimable(address[] calldata accounts, bool newStatus) public onlyOwner {
    _updateClaimable(accounts, newStatus);
  }

  /// @inheritdoc IKEMHook
  function updateWhitelisted(address[] calldata accounts, bool newStatus) public onlyOwner {
    _updateWhitelisted(accounts, newStatus);
  }

  /// @inheritdoc IKEMHook
  function updateQuoteSigner(address newSigner) public onlyOwner {
    _updateQuoteSigner(newSigner);
  }

  /// @inheritdoc IKEMHook
  function updateEgRecipient(address newRecipient) public onlyOwner {
    _updateEgRecipient(newRecipient);
  }

  function _updateClaimable(address[] memory accounts, bool newStatus) internal {
    for (uint256 i = 0; i < accounts.length; i++) {
      claimable[accounts[i]] = newStatus;

      emit UpdateClaimable(accounts[i], newStatus);
    }
  }

  function _updateWhitelisted(address[] memory accounts, bool newStatus) internal {
    for (uint256 i = 0; i < accounts.length; i++) {
      whitelisted[accounts[i]] = newStatus;

      emit UpdateWhitelisted(accounts[i], newStatus);
    }
  }

  function _updateQuoteSigner(address newSigner) internal {
    require(newSigner != address(0), InvalidAddress());
    quoteSigner = newSigner;

    emit UpdateQuoteSigner(newSigner);
  }

  function _updateEgRecipient(address newRecipient) internal {
    require(newRecipient != address(0), InvalidAddress());
    egRecipient = newRecipient;

    emit UpdateEgRecipient(newRecipient);
  }

  function _checkOwner() internal view override(Rescuable, Ownable) {
    Ownable._checkOwner();
  }
}
