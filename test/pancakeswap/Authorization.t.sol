// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// import './Base.t.sol';

// contract PancakeSwapHookAuthorizationTest is PancakeSwapHookBaseTest {
//   /// forge-config: default.fuzz.runs = 20
//   function test_pancakeswap_updateClaimable_succeed(address sender, bool newStatus) public {
//     vm.prank(owner);
//     vm.expectEmit(true, true, true, true, address(hook));
//     emit IKEMHook.UpdateClaimable(sender, newStatus);
//     hook.updateClaimable(newAddressArray(sender), newStatus);
//     assertEq(hook.claimable(sender), newStatus);
//   }

//   /// forge-config: default.fuzz.runs = 20
//   function test_pancakeswap_updateClaimable_notOwner_shouldFail(
//     uint256 actorIndex,
//     address sender,
//     bool newStatus
//   ) public {
//     address actor = actors[bound(actorIndex, 0, actors.length - 1)];
//     vm.assume(actor != owner);
//     vm.prank(actor);
//     vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actor));
//     hook.updateClaimable(newAddressArray(sender), newStatus);
//   }

//   /// forge-config: default.fuzz.runs = 20
//   function test_pancakeswap_updateQuoteSigner_succeed(address newSigner) public {
//     vm.assume(newSigner != address(0));
//     vm.prank(owner);
//     vm.expectEmit(true, true, true, true, address(hook));
//     emit IKEMHook.UpdateQuoteSigner(newSigner);
//     hook.updateQuoteSigner(newSigner);
//     assertEq(hook.quoteSigner(), newSigner);
//   }

//   /// forge-config: default.fuzz.runs = 20
//   function test_pancakeswap_updateQuoteSigner_notOwner_shouldFail(
//     uint256 actorIndex,
//     address newSigner
//   ) public {
//     vm.assume(newSigner != address(0));
//     address actor = actors[bound(actorIndex, 0, actors.length - 1)];
//     vm.assume(actor != owner);
//     vm.prank(actor);
//     vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actor));
//     hook.updateQuoteSigner(newSigner);
//   }

//   /// forge-config: default.fuzz.runs = 20
//   function test_pancakeswap_updateEGRecipient_succeed(address recipient) public {
//     vm.assume(recipient != address(0));
//     vm.prank(owner);
//     vm.expectEmit(true, true, true, true, address(hook));
//     emit IKEMHook.UpdateEGRecipient(recipient);
//     hook.updateEGRecipient(recipient);
//     assertEq(hook.egRecipient(), recipient);
//   }

//   /// forge-config: default.fuzz.runs = 20
//   function test_pancakeswap_updateEGRecipient_notOwner_shouldFail(
//     uint256 actorIndex,
//     address recipient
//   ) public {
//     vm.assume(recipient != address(0));
//     address actor = actors[bound(actorIndex, 0, actors.length - 1)];
//     vm.assume(actor != owner);
//     vm.prank(actor);
//     vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, actor));
//     hook.updateEGRecipient(recipient);
//   }

//   function test_pancakeswap_updateQuoteSigner_with_zeroAddress() public {
//     vm.prank(owner);
//     vm.expectRevert(ICommon.InvalidAddress.selector);
//     hook.updateQuoteSigner(address(0));
//   }

//   function test_pancakeswap_updateEGRecipient_with_zeroAddress() public {
//     vm.prank(owner);
//     vm.expectRevert(ICommon.InvalidAddress.selector);
//     hook.updateEGRecipient(address(0));
//   }
// }
