// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract UniswapHookAdminTest is UniswapHookBaseTest {
  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_admin_updateQuoteSigner(address newSigner) public {
    vm.prank(admin);
    if (newSigner == address(0)) {
      vm.expectRevert(ICommon.InvalidAddress.selector);
    }
    hook.updateQuoteSigner(newSigner);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_others_updateQuoteSigner_fail(uint256 actorIndex, address newSigner) public {
    address actor = actors[bound(actorIndex, 0, actors.length - 1)];
    vm.assume(actor != admin);

    vm.prank(actor);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, actor, 0x00)
    );
    hook.updateQuoteSigner(newSigner);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_admin_updateEGRecipient(address newEGRecipient) public {
    vm.prank(admin);
    if (newEGRecipient == address(0)) {
      vm.expectRevert(ICommon.InvalidAddress.selector);
    }
    hook.updateEGRecipient(newEGRecipient);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_others_updateEGRecipient_fail(uint256 actorIndex, address newEGRecipient)
    public
  {
    address actor = actors[bound(actorIndex, 0, actors.length - 1)];
    vm.assume(actor != admin);

    vm.prank(actor);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, actor, 0x00)
    );
    hook.updateEGRecipient(newEGRecipient);
  }

  function test_uniswap_admin_pause() public {
    vm.prank(admin);
    Management(address(hook)).pause();
  }

  function test_uniswap_guardian_pause() public {
    vm.prank(guardian);
    Management(address(hook)).pause();
  }

  function test_uniswap_unpause_fail() public {
    vm.prank(guardian);
    vm.expectRevert(IFFHookAdmin.UnpauseDisabled.selector);
    Management(address(hook)).unpause();

    vm.prank(admin);
    vm.expectRevert(IFFHookAdmin.UnpauseDisabled.selector);
    Management(address(hook)).unpause();
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_admin_or_operator_claimProtocolEGs(
    uint256 mintAmount0,
    uint256 mintAmount1,
    uint256 claimAmount0,
    uint256 claimAmount1
  ) public {
    mintAmount0 = bound(mintAmount0, 0, uint128(type(int128).max));
    mintAmount1 = bound(mintAmount1, 0, uint128(type(int128).max));
    claimAmount0 = bound(claimAmount0, 0, mintAmount0);
    claimAmount1 = bound(claimAmount1, 0, mintAmount1);
    manager.unlock(abi.encode(mintAmount0, mintAmount1));

    IFFHookHarness(address(hook)).updateProtocolEGUnclaimed(Currency.unwrap(currency0), mintAmount0);
    IFFHookHarness(address(hook)).updateProtocolEGUnclaimed(Currency.unwrap(currency1), mintAmount1);

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = claimAmount0 == 0 ? mintAmount0 : claimAmount0;
    amounts[1] = claimAmount1 == 0 ? mintAmount1 : claimAmount1;

    vm.prank(mintAmount0 % 2 == 0 ? admin : operator);
    vm.expectEmit(true, true, true, true, address(hook));
    emit IFFHookAdmin.ClaimProtocolEGs(egRecipient, tokens, amounts);
    amounts[0] = claimAmount0;
    amounts[1] = claimAmount1;
    hook.claimProtocolEGs(tokens, amounts);

    assertEq(currency0.balanceOf(egRecipient), claimAmount0 == 0 ? mintAmount0 : claimAmount0);
    assertEq(currency1.balanceOf(egRecipient), claimAmount1 == 0 ? mintAmount1 : claimAmount1);

    assertEq(
      hook.protocolEGUnclaimed(tokens[0]),
      mintAmount0 - (claimAmount0 == 0 ? mintAmount0 : claimAmount0)
    );
    assertEq(
      hook.protocolEGUnclaimed(tokens[1]),
      mintAmount1 - (claimAmount1 == 0 ? mintAmount1 : claimAmount1)
    );
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_admin_or_operator_claimProtocolEGs_native(
    uint256 mintAmount,
    uint256 claimAmount
  ) public {
    mintAmount = bound(mintAmount, 0, uint128(type(int128).max));
    claimAmount = bound(claimAmount, 0, mintAmount);
    manager.unlock(abi.encode(mintAmount, type(uint256).max));

    IFFHookHarness(address(hook)).updateProtocolEGUnclaimed(address(0), mintAmount);

    tokens = newAddressArray(address(0));
    uint256[] memory amounts = newUint256Array(claimAmount == 0 ? mintAmount : claimAmount);

    vm.prank(mintAmount % 2 == 0 ? admin : operator);
    vm.expectEmit(true, true, true, true, address(hook));
    emit IFFHookAdmin.ClaimProtocolEGs(egRecipient, tokens, amounts);
    amounts[0] = claimAmount;
    hook.claimProtocolEGs(tokens, amounts);

    assertEq(egRecipient.balance, claimAmount == 0 ? mintAmount : claimAmount);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_others_claimProtocolEGs_fail(
    uint256 actorIndex,
    uint256 claimAmount0,
    uint256 claimAmount1
  ) public {
    address actor = actors[bound(actorIndex, 0, actors.length - 1)];
    vm.assume(actor != admin && actor != operator);

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = claimAmount0;
    amounts[1] = claimAmount1;

    vm.prank(actor);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, actor, KSRoles.OPERATOR_ROLE
      )
    );
    hook.claimProtocolEGs(tokens, amounts);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_admin_or_rescuer_rescueEGs(
    uint256 mintAmount0,
    uint256 mintAmount1,
    uint256 rescueAmount0,
    uint256 rescueAmount1
  ) public {
    mintAmount0 = bound(mintAmount0, 0, uint128(type(int128).max));
    mintAmount1 = bound(mintAmount1, 0, uint128(type(int128).max));
    rescueAmount0 = bound(rescueAmount0, 0, mintAmount0);
    rescueAmount1 = bound(rescueAmount1, 0, mintAmount1);
    manager.unlock(abi.encode(mintAmount0, mintAmount1));

    address[] memory tokens = new address[](2);
    tokens[0] = Currency.unwrap(currency0);
    tokens[1] = Currency.unwrap(currency1);
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = rescueAmount0 == 0 ? mintAmount0 : rescueAmount0;
    amounts[1] = rescueAmount1 == 0 ? mintAmount1 : rescueAmount1;

    // before pausing the hook
    vm.prank(mintAmount0 % 2 == 0 ? admin : rescuer);
    vm.expectRevert(Pausable.ExpectedPause.selector);
    hook.rescueEGs(tokens, amounts);

    // after pausing the hook
    vm.prank(guardian);
    Management(address(hook)).pause();

    vm.prank(mintAmount0 % 2 == 0 ? admin : rescuer);
    vm.expectEmit(true, true, true, true, address(hook));
    emit IFFHookAdmin.RescueEGs(egRecipient, tokens, amounts);
    amounts[0] = rescueAmount0;
    amounts[1] = rescueAmount1;
    hook.rescueEGs(tokens, amounts);

    assertEq(currency0.balanceOf(egRecipient), rescueAmount0 == 0 ? mintAmount0 : rescueAmount0);
    assertEq(currency1.balanceOf(egRecipient), rescueAmount1 == 0 ? mintAmount1 : rescueAmount1);
  }

  /// forge-config: default.fuzz.runs = 20
  function test_uniswap_others_rescueEGs_fail(
    uint256 actorIndex,
    uint256 rescueAmount0,
    uint256 rescueAmount1
  ) public {
    address actor = actors[bound(actorIndex, 0, actors.length - 1)];
    vm.assume(actor != admin && actor != rescuer);

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = rescueAmount0;
    amounts[1] = rescueAmount1;

    vm.prank(guardian);
    Management(address(hook)).pause();

    vm.prank(actor);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, actor, KSRoles.RESCUER_ROLE
      )
    );
    hook.rescueEGs(tokens, amounts);
  }

  function unlockCallback(bytes calldata data) public returns (bytes memory) {
    (uint256 mintAmount0, uint256 mintAmount1) = abi.decode(data, (uint256, uint256));

    if (mintAmount1 == type(uint256).max) {
      manager.mint(address(hook), 0, mintAmount0);

      manager.sync(CurrencyLibrary.ADDRESS_ZERO);
      manager.settle{value: mintAmount0}();
    } else {
      manager.mint(address(hook), uint256(uint160(Currency.unwrap(currency0))), mintAmount0);
      manager.mint(address(hook), uint256(uint160(Currency.unwrap(currency1))), mintAmount1);

      manager.sync(currency0);
      currency0.transfer(address(manager), mintAmount0);
      manager.settle();

      manager.sync(currency1);
      currency1.transfer(address(manager), mintAmount1);
      manager.settle();
    }
  }
}
