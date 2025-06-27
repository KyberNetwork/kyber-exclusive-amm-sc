// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKEMHookV2Admin} from '../interfaces/IKEMHookV2Admin.sol';
import {IKEMHookV2Errors} from '../interfaces/IKEMHookV2Errors.sol';
import {IKEMHookV2Events} from '../interfaces/IKEMHookV2Events.sol';

import {BaseKEMHookV2Accounting} from './BaseKEMHookV2Accounting.sol';
import {BaseKEMHookV2State} from './BaseKEMHookV2State.sol';

import {Management} from 'ks-common-sc/src/base/Management.sol';
import {Rescuable} from 'ks-common-sc/src/base/Rescuable.sol';

abstract contract BaseKEMHookV2Admin is
  IKEMHookV2Admin,
  IKEMHookV2Errors,
  IKEMHookV2Events,
  BaseKEMHookV2State,
  BaseKEMHookV2Accounting,
  Management,
  Rescuable
{
  /// @inheritdoc IKEMHookV2Admin
  function updateQuoteSigner(address newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateQuoteSigner(newSigner);
  }

  function _updateQuoteSigner(address newSigner) internal {
    require(newSigner != address(0), InvalidAddress());

    address oldSigner = quoteSigner;
    quoteSigner = newSigner;

    emit UpdateQuoteSigner(oldSigner, newSigner);
  }

  /// @inheritdoc IKEMHookV2Admin
  function updateEGRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateEGRecipient(newRecipient);
  }

  function _updateEGRecipient(address newRecipient) internal {
    require(newRecipient != address(0), InvalidAddress());

    address oldRecipient = egRecipient;
    egRecipient = newRecipient;

    emit UpdateEGRecipient(oldRecipient, newRecipient);
  }

  /// @inheritdoc IKEMHookV2Admin
  function updateProtocolEGFee(bytes32 poolId, uint24 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(newFee <= PIPS_DENOMINATOR, TooLargeProtocolEGFee(newFee));

    uint24 oldFee = pools[poolId].protocolEGFee;
    pools[poolId].protocolEGFee = newFee;

    emit UpdateProtocolEGFee(poolId, oldFee, newFee);
  }

  /// @notice Internal logic for `claimProtocolEG`
  function _claimProtocolEG(bytes calldata data) internal {
    (address[] memory tokens, uint256[] memory amounts) = abi.decode(data, (address[], uint256[]));
    address _egRecipient = egRecipient;

    for (uint256 i = 0; i < tokens.length; i++) {
      address token = tokens[i];

      uint256 amount = amounts[i];
      if (amount == 0) {
        amount = protocolEGUnclaimed[token];
      }

      if (amount > 0) {
        amounts[i] = amount;
        protocolEGUnclaimed[token] -= amount;
        _take(token, _egRecipient, amount);
      }
    }

    emit ClaimProtocolEG(_egRecipient, tokens, amounts);
  }
}
