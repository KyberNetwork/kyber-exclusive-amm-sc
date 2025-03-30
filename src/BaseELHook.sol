// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IELHook} from './interfaces/IELHook.sol';

import {KSRescueV2, KyberSwapRole, Ownable} from 'ks-growth-utils-sc/KSRescueV2.sol';

/**
 * @title BaseELHook
 * @notice Abstract contract containing common implementation for ELHook contracts
 */
abstract contract BaseELHook is IELHook, KSRescueV2 {
  /// @inheritdoc IELHook
  mapping(address => bool) public whitelisted;

  /// @inheritdoc IELHook
  address public quoteSigner;

  /// @inheritdoc IELHook
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

  /// @inheritdoc IELHook
  function whitelistSenders(address[] calldata senders, bool grantOrRevoke) public onlyOwner {
    for (uint256 i = 0; i < senders.length; i++) {
      whitelisted[senders[i]] = grantOrRevoke;

      emit ELHookWhitelistSender(senders[i], grantOrRevoke);
    }
  }

  /// @inheritdoc IELHook
  function updateQuoteSigner(address newSigner) public onlyOwner {
    _updateQuoteSigner(newSigner);
  }

  /// @inheritdoc IELHook
  function updateSurplusRecipient(address newRecipient) public onlyOwner {
    _updateSurplusRecipient(newRecipient);
  }

  function _updateQuoteSigner(address newSigner) internal {
    require(newSigner != address(0), ELHookInvalidAddress());
    quoteSigner = newSigner;

    emit ELHookUpdateQuoteSigner(newSigner);
  }

  function _updateSurplusRecipient(address newRecipient) internal {
    require(newRecipient != address(0), ELHookInvalidAddress());
    surplusRecipient = newRecipient;

    emit ELHookUpdateSurplusRecipient(newRecipient);
  }
}
