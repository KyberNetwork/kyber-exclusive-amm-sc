// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseKEMHookV2Admin} from './BaseKEMHookV2Admin.sol';
import {BaseKEMHookV2AfterSwap} from './BaseKEMHookV2AfterSwap.sol';
import {BaseKEMHookV2BeforeSwap} from './BaseKEMHookV2BeforeSwap.sol';
import {BaseKEMHookV2Subscriber} from './BaseKEMHookV2Subscriber.sol';

import {PoolStateView} from './PoolStateView.sol';
import {BaseKEMHookV2Accounting} from './BaseKEMHookV2Accounting.sol';

import {Management} from 'ks-common-sc/src/base/Management.sol';

abstract contract BaseKEMHookV2 is
  BaseKEMHookV2Admin,
  BaseKEMHookV2BeforeSwap,
  BaseKEMHookV2AfterSwap,
  BaseKEMHookV2Subscriber
{
  constructor(
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialClaimants
  ) Management(initialAdmin) {
    _updateQuoteSigner(initialQuoteSigner);
    _updateEGRecipient(initialEgRecipient);

    for (uint256 i = 0; i < initialClaimants.length; i++) {
      _grantRole(CLAIM_ROLE, initialClaimants[i]);
    }
  }
}
