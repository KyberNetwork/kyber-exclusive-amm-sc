// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFFHookAdmin} from '../interfaces/modules/IFFHookAdmin.sol';

import {FFHookAccounting} from './FFHookAccounting.sol';
import {FFHookStorage} from './FFHookStorage.sol';

import {Management} from 'ks-common-sc/src/base/Management.sol';
import {Rescuable} from 'ks-common-sc/src/base/Rescuable.sol';
import {KSRoles} from 'ks-common-sc/src/libraries/KSRoles.sol';

import {MathExt} from '../libraries/MathExt.sol';

abstract contract FFHookAdmin is
  IFFHookAdmin,
  FFHookStorage,
  FFHookAccounting,
  Management,
  Rescuable
{
  constructor(
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialOperators
  ) Management(initialAdmin) {
    _updateQuoteSigner(initialQuoteSigner);
    _updateEGRecipient(initialEgRecipient);
    _batchGrantRole(KSRoles.OPERATOR_ROLE, initialOperators);
  }

  /// @inheritdoc IFFHookAdmin
  function updateQuoteSigner(address newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateQuoteSigner(newSigner);
  }

  function _updateQuoteSigner(address newSigner) internal {
    require(newSigner != address(0), InvalidAddress());

    address oldSigner = quoteSigner;
    quoteSigner = newSigner;

    emit UpdateQuoteSigner(oldSigner, newSigner);
  }

  /// @inheritdoc IFFHookAdmin
  function updateEGRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateEGRecipient(newRecipient);
  }

  function _updateEGRecipient(address newRecipient) internal {
    require(newRecipient != address(0), InvalidAddress());

    address oldRecipient = egRecipient;
    egRecipient = newRecipient;

    emit UpdateEGRecipient(oldRecipient, newRecipient);
  }

  /// @inheritdoc IFFHookAdmin
  function updateProtocolEGFee(bytes32 poolId, uint24 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(newFee <= MathExt.PIPS_DENOMINATOR, TooLargeProtocolEGFee(newFee));

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
        _burn(token, amount);
        _take(token, _egRecipient, amount);
      }
    }

    emit ClaimProtocolEG(_egRecipient, tokens, amounts);
  }
}
