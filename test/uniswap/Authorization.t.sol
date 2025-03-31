// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract UniswapHookAuthorizationTest is UniswapHookBaseTest {
  /// forge-config: default.fuzz.runs = 5
  function test_uniswap_updateWhitelist_succeed(address sender, bool grantOrRevoke) public {
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IKEMHook.WhitelistSender(sender, grantOrRevoke);
    IKEMHook(hook).whitelistSenders(newAddressesLength1(sender), grantOrRevoke);
    assertEq(IKEMHook(hook).whitelisted(sender), grantOrRevoke);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_uniswap_updateWhitelist_notOwner_shouldFail(
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
  function test_uniswap_updateQuoteSigner_succeed(address newSigner) public {
    vm.assume(newSigner != address(0));
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IKEMHook.UpdateQuoteSigner(newSigner);
    IKEMHook(hook).updateQuoteSigner(newSigner);
    assertEq(IKEMHook(hook).quoteSigner(), newSigner);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_uniswap_updateQuoteSigner_notOwner_shouldFail(
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
  function test_uniswap_updateSurplusRecipient_succeed(address recipient) public {
    vm.assume(recipient != address(0));
    vm.prank(owner);
    vm.expectEmit(true, true, true, true, hook);
    emit IKEMHook.UpdateSurplusRecipient(recipient);
    IKEMHook(hook).updateSurplusRecipient(recipient);
    assertEq(IKEMHook(hook).surplusRecipient(), recipient);
  }

  /// forge-config: default.fuzz.runs = 5
  function test_uniswap_updateSurplusRecipient_notOwner_shouldFail(
    uint256 addressIndex,
    address recipient
  ) public {
    vm.assume(recipient != address(0));
    address actor = actorAddresses[bound(addressIndex, 0, actorAddresses.length - 1)];
    vm.assume(actor != owner);
    vm.prank(actor);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actor));
    IKEMHook(hook).updateSurplusRecipient(recipient);
  }

  function test_uniswap_updateQuoteSigner_with_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IKEMHook.InvalidAddress.selector);
    IKEMHook(hook).updateQuoteSigner(address(0));
  }

  function test_uniswap_updateSurplusRecipient_with_zeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IKEMHook.InvalidAddress.selector);
    IKEMHook(hook).updateSurplusRecipient(address(0));
  }
}
