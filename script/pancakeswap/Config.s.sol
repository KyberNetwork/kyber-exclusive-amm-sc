// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.s.sol';
import 'src/interfaces/IKEMHook.sol';

contract ConfigScript is BasePancakeSwapScript {
  address[] notWhitelisted;
  address[] notClaimable;

  function run() public {
    for (uint256 i; i < whitelistedAccounts.length; ++i) {
      if (!IKEMHook(address(hook)).whitelisted(whitelistedAccounts[i])) {
        notWhitelisted.push(whitelistedAccounts[i]);
      }
    }

    for (uint256 i; i < claimableAccounts.length; ++i) {
      if (!IKEMHook(address(hook)).claimable(claimableAccounts[i])) {
        notClaimable.push(claimableAccounts[i]);
      }
    }

    vm.startBroadcast();
    if (notWhitelisted.length > 0) {
      IKEMHook(address(hook)).updateWhitelisted(notWhitelisted, true);
    }
    if (notClaimable.length > 0) {
      IKEMHook(address(hook)).updateClaimable(notClaimable, true);
    }
    if (IKEMHook(address(hook)).egRecipient() != egRecipient) {
      IKEMHook(address(hook)).updateEgRecipient(egRecipient);
    }
    if (IKEMHook(address(hook)).quoteSigner() != quoteSigner) {
      IKEMHook(address(hook)).updateQuoteSigner(quoteSigner);
    }
    vm.stopBroadcast();
  }
}
