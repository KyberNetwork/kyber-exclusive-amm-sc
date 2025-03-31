// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract PancakeSwapHookAuthorizationTest is PancakeSwapHookBaseTest {
  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_grantRole_succeed(address account, uint256 roleIndex) public {
    bytes32 role = roles[bound(roleIndex, 0, roles.length - 1)];

    vm.prank(admin);
    vm.expectEmit(true, true, true, true, address(hook));
    emit IAccessControl.RoleGranted(role, account, admin);
    hook.grantRole(role, account);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_grantNewAdminRole_should_revokeOldAdminRole(address newAdmin) public {
    vm.assume(newAdmin != admin);

    vm.prank(admin);
    vm.expectEmit(true, true, true, true, address(hook));
    emit IAccessControl.RoleRevoked(DEFAULT_ADMIN_ROLE, admin, admin);
    vm.expectEmit(true, true, true, true, address(hook));
    emit IAccessControl.RoleGranted(DEFAULT_ADMIN_ROLE, newAdmin, admin);
    hook.grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_grantRole_withoutAdminRole_shouldFail(
    uint256 actorIndex,
    address account,
    uint256 roleIndex
  ) public {
    address actor = actors[bound(actorIndex, 0, actors.length - 1)];
    bytes32 role = roles[bound(roleIndex, 0, roles.length - 1)];
    vm.assume(actor != admin);

    vm.prank(actor);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, actor, DEFAULT_ADMIN_ROLE
      )
    );
    hook.grantRole(role, account);
  }

  function test_pancakeswap_revokeAdminRole_shouldFail() public {
    vm.prank(admin);
    vm.expectRevert(IKEMHook.RevokeAdminRoleDisabled.selector);
    hook.revokeRole(DEFAULT_ADMIN_ROLE, admin);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_updateQuoteSigner_succeed(address newSigner) public {
    vm.assume(newSigner != address(0));

    vm.prank(admin);
    vm.expectEmit(true, true, true, true, address(hook));
    emit IKEMHook.UpdateQuoteSigner(newSigner);
    hook.updateQuoteSigner(newSigner);
    assertEq(hook.quoteSigner(), newSigner);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_updateQuoteSigner_withoutAdminRole_shouldFail(
    uint256 actorIndex,
    address newSigner
  ) public {
    vm.assume(newSigner != address(0));
    address actor = actors[bound(actorIndex, 0, actors.length - 1)];
    vm.assume(actor != admin);

    vm.prank(actor);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, actor, DEFAULT_ADMIN_ROLE
      )
    );
    hook.updateQuoteSigner(newSigner);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_updateEgRecipient_succeed(address recipient) public {
    vm.assume(recipient != address(0));

    vm.prank(admin);
    vm.expectEmit(true, true, true, true, address(hook));
    emit IKEMHook.UpdateEgRecipient(recipient);
    hook.updateEgRecipient(recipient);
    assertEq(hook.egRecipient(), recipient);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_updateEgRecipient_withoutAdminRole_shouldFail(
    uint256 actorIndex,
    address recipient
  ) public {
    vm.assume(recipient != address(0));
    address actor = actors[bound(actorIndex, 0, actors.length - 1)];
    vm.assume(actor != admin);

    vm.prank(actor);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, actor, DEFAULT_ADMIN_ROLE
      )
    );
    hook.updateEgRecipient(recipient);
  }

  function test_pancakeswap_updateQuoteSigner_with_zeroAddress() public {
    vm.prank(admin);
    vm.expectRevert(IKEMHook.InvalidAddress.selector);
    hook.updateQuoteSigner(address(0));
  }

  function test_pancakeswap_updateEgRecipient_with_zeroAddress() public {
    vm.prank(admin);
    vm.expectRevert(IKEMHook.InvalidAddress.selector);
    hook.updateEgRecipient(address(0));
  }
}
