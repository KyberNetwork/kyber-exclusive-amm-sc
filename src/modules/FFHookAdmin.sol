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
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address[] memory initialRescuers
  ) Management(initialAdmin) {
    _updateQuoteSigner(initialQuoteSigner);
    _updateEGRecipient(initialEgRecipient);

    _grantRole(KSRoles.OPERATOR_ROLE, initialAdmin);
    _batchGrantRole(KSRoles.OPERATOR_ROLE, initialOperators);

    _grantRole(KSRoles.GUARDIAN_ROLE, initialAdmin);
    _batchGrantRole(KSRoles.GUARDIAN_ROLE, initialGuardians);

    _grantRole(KSRoles.RESCUER_ROLE, initialAdmin);
    _batchGrantRole(KSRoles.RESCUER_ROLE, initialRescuers);
  }

  /// @inheritdoc IFFHookAdmin
  function updateQuoteSigner(address newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateQuoteSigner(newSigner);
  }

  function _updateQuoteSigner(address newSigner) internal checkAddress(newSigner) {
    address oldSigner = quoteSigner;
    quoteSigner = newSigner;

    emit UpdateQuoteSigner(oldSigner, newSigner);
  }

  /// @inheritdoc IFFHookAdmin
  function updateEGRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateEGRecipient(newRecipient);
  }

  function _updateEGRecipient(address newRecipient) internal checkAddress(newRecipient) {
    address oldRecipient = egRecipient;
    egRecipient = newRecipient;

    emit UpdateEGRecipient(oldRecipient, newRecipient);
  }

  /// @inheritdoc IFFHookAdmin
  function updateProtocolEGFee(bytes32 poolId, uint24 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (newFee > MathExt.PIPS_DENOMINATOR) {
      revert TooLargeProtocolEGFee(newFee);
    }

    uint24 oldFee = pools[poolId].protocolEGFee;
    pools[poolId].protocolEGFee = newFee;

    emit UpdateProtocolEGFee(poolId, oldFee, newFee);
  }

  /// @inheritdoc IFFHookAdmin
  function claimProtocolEGs(address[] memory tokens, uint256[] memory amounts)
    external
    onlyRole(KSRoles.OPERATOR_ROLE)
    checkLengths(tokens.length, amounts.length)
  {
    for (uint256 i = 0; i < tokens.length; i++) {
      if (amounts[i] == 0) {
        amounts[i] = protocolEGUnclaimed[tokens[i]];
      }
      protocolEGUnclaimed[tokens[i]] -= amounts[i];
    }

    _lockOrUnlock(abi.encode(tokens, amounts));

    emit ClaimProtocolEGs(egRecipient, tokens, amounts);
  }

  /// @inheritdoc IFFHookAdmin
  function rescueEGs(address[] memory tokens, uint256[] memory amounts)
    external
    whenPaused
    onlyRole(KSRoles.RESCUER_ROLE)
    checkLengths(tokens.length, amounts.length)
  {
    for (uint256 i = 0; i < tokens.length; i++) {
      if (amounts[i] == 0) {
        amounts[i] = _getTotalEGUnclaimed(tokens[i]);
      }
    }

    _lockOrUnlock(abi.encode(tokens, amounts));

    emit RescueEGs(egRecipient, tokens, amounts);
  }

  /// @notice Disallow unpausing the hook
  function _unpause() internal override {
    revert UnpauseDisabled();
  }
}
