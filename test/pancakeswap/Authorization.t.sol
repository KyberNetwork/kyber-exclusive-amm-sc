// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract PancakeswapHookAuthorizationTest is PancakeswapHookBaseTest {
  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateWhitelist_succeed(address sender, bool grantOrRevoke) public {
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookWhitelistSender(sender, grantOrRevoke);
    IELHook(hook).whitelistSenders(newAddressesLength1(sender), grantOrRevoke);
    assertEq(IELHook(hook).whitelisted(sender), grantOrRevoke);
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
    IELHook(hook).whitelistSenders(newAddressesLength1(sender), grantOrRevoke);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateQuoteSigner_succeed(address newSigner) public {
    vm.assume(newSigner != address(0));
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookUpdateQuoteSigner(newSigner);
    IELHook(hook).updateQuoteSigner(newSigner);
    assertEq(IELHook(hook).quoteSigner(), newSigner);
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
    IELHook(hook).updateQuoteSigner(newSigner);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateSurplusRecipient_succeed(address recipient) public {
    vm.assume(recipient != address(0));
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookUpdateSurplusRecipient(recipient);
    IELHook(hook).updateSurplusRecipient(recipient);
    assertEq(IELHook(hook).surplusRecipient(), recipient);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_pancakeswap_updateSurplusRecipient_notOwner_shouldFail(
    uint256 addressIndex,
    address recipient
  ) public {
    vm.assume(recipient != address(0));
    address actor = actorAddresses[bound(addressIndex, 0, actorAddresses.length - 1)];
    vm.assume(actor != owner);
    vm.prank(actor);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actor));
    IELHook(hook).updateSurplusRecipient(recipient);
  }

  function test_pancakeswap_updateQuoteSigner_with_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IELHook.ELHookInvalidAddress.selector);
    IELHook(hook).updateQuoteSigner(address(0));
  }

  function test_pancakeswap_updateSurplusRecipient_with_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IELHook.ELHookInvalidAddress.selector);
    IELHook(hook).updateSurplusRecipient(address(0));
  }
}
