// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract PancakeSwapHookAuthorizationTest is PancakeSwapHookBaseTest {
  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateWhitelist_succeed(address sender, bool grantOrRevoke) public {
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IKEMHook.WhitelistSender(sender, grantOrRevoke);
    IKEMHook(hook).whitelistSenders(newAddressesLength1(sender), grantOrRevoke);
    assertEq(IKEMHook(hook).whitelisted(sender), grantOrRevoke);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateWhitelist_notOwner_shouldFail(
    uint256 addressIndex,
    address sender,
    bool grantOrRevoke
  ) public {
    address actor = actorAddresses[bound(addressIndex, 0, actorAddresses.length - 1)];
    vm.assume(actor != owner);
    vm.prank(actor);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actor));
    IKEMHook(hook).whitelistSenders(newAddressesLength1(sender), grantOrRevoke);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateQuoteSigner_succeed(address newSigner) public {
    vm.assume(newSigner != address(0));
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IKEMHook.UpdateQuoteSigner(newSigner);
    IKEMHook(hook).updateQuoteSigner(newSigner);
    assertEq(IKEMHook(hook).quoteSigner(), newSigner);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateQuoteSigner_notOwner_shouldFail(
    uint256 addressIndex,
    address newSigner
  ) public {
    vm.assume(newSigner != address(0));
    address actor = actorAddresses[bound(addressIndex, 0, actorAddresses.length - 1)];
    vm.assume(actor != owner);
    vm.prank(actor);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actor));
    IKEMHook(hook).updateQuoteSigner(newSigner);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateEGRecipient_succeed(address recipient) public {
    vm.assume(recipient != address(0));
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IKEMHook.UpdateEGRecipient(recipient);
    IKEMHook(hook).updateEGRecipient(recipient);
    assertEq(IKEMHook(hook).egRecipient(), recipient);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateEGRecipient_notOwner_shouldFail(
    uint256 addressIndex,
    address recipient
  ) public {
    vm.assume(recipient != address(0));
    address actor = actorAddresses[bound(addressIndex, 0, actorAddresses.length - 1)];
    vm.assume(actor != owner);
    vm.prank(actor);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actor));
    IKEMHook(hook).updateEGRecipient(recipient);
  }

  function test_pancakeswap_updateQuoteSigner_with_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IKEMHook.InvalidAddress.selector);
    IKEMHook(hook).updateQuoteSigner(address(0));
  }

  function test_pancakeswap_updateEGRecipient_with_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IKEMHook.InvalidAddress.selector);
    IKEMHook(hook).updateEGRecipient(address(0));
  }
}
