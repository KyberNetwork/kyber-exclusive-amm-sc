// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKEMHook} from './interfaces/IKEMHook.sol';

import {KSRescueV2, KyberSwapRole, Ownable} from 'ks-growth-utils-sc/KSRescueV2.sol';

/**
 * @title BaseKEMHook
 * @notice Abstract contract containing common implementation for KEMHook contracts
 */
abstract contract BaseKEMHook is IKEMHook, KSRescueV2 {
  /// @inheritdoc IKEMHook
  mapping(address => bool) public whitelisted;

  /// @inheritdoc IKEMHook
  address public quoteSigner;

  /// @inheritdoc IKEMHook
  address public surplusRecipient;

  constructor(
    address initialOwner,
    address[] memory initialOperators,
    address initialSigner,
    address initialSurplusRecipient
  ) Ownable(initialOwner) {
    for (uint256 i = 0; i < initialOperators.length; i++) {
      operators[initialOperators[i]] = true;

      emit UpdateOperator(initialOperators[i], true);
    }

    _updateQuoteSigner(initialSigner);
    _updateSurplusRecipient(initialSurplusRecipient);
  }

  /// @inheritdoc IKEMHook
  function whitelistSenders(address[] calldata senders, bool grantOrRevoke) public onlyOwner {
    for (uint256 i = 0; i < senders.length; i++) {
      whitelisted[senders[i]] = grantOrRevoke;

      emit WhitelistSender(senders[i], grantOrRevoke);
    }
  }

  /// @inheritdoc IKEMHook
  function updateQuoteSigner(address newSigner) public onlyOwner {
    _updateQuoteSigner(newSigner);
  }

  /// @inheritdoc IKEMHook
  function updateSurplusRecipient(address newRecipient) public onlyOwner {
    _updateSurplusRecipient(newRecipient);
  }

  function _updateQuoteSigner(address newSigner) internal {
    require(newSigner != address(0), InvalidAddress());
    quoteSigner = newSigner;

    emit UpdateQuoteSigner(newSigner);
  }

  function _updateSurplusRecipient(address newRecipient) internal {
    require(newRecipient != address(0), InvalidAddress());
    surplusRecipient = newRecipient;

    emit UpdateSurplusRecipient(newRecipient);
  }
}
