// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.t.sol';

contract PancakeswapHookClaimSurplusTest is PancakeswapHookBaseTest {
  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_claimSurplusTokens_succeed(
    uint256 mintAmount0,
    uint256 mintAmount1,
    uint256 claimAmount0,
    uint256 claimAmount1
  ) public {
    mintAmount0 = bound(mintAmount0, 0, uint128(type(int128).max));
    mintAmount1 = bound(mintAmount1, 0, uint128(type(int128).max));
    claimAmount0 = bound(claimAmount0, 0, mintAmount0);
    claimAmount1 = bound(claimAmount1, 0, mintAmount1);
    vault.lock(abi.encode(mintAmount0, mintAmount1));

    address[] memory tokens = new address[](2);
    tokens[0] = Currency.unwrap(currency0);
    tokens[1] = Currency.unwrap(currency1);
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = claimAmount0 == 0 ? mintAmount0 : claimAmount0;
    amounts[1] = claimAmount1 == 0 ? mintAmount1 : claimAmount1;

    uint256 recipientAmount0Before = IERC20(Currency.unwrap(currency0)).balanceOf(surplusRecipient);
    uint256 recipientAmount1Before = IERC20(Currency.unwrap(currency1)).balanceOf(surplusRecipient);

    vm.prank(operator);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookClaimSurplusTokens(surplusRecipient, tokens, amounts);
    amounts[0] = claimAmount0;
    amounts[1] = claimAmount1;
    IELHook(hook).claimSurplusTokens(tokens, amounts);

    assertEq(
      IERC20(Currency.unwrap(currency0)).balanceOf(surplusRecipient),
      claimAmount0 == 0 ? mintAmount0 : claimAmount0 + recipientAmount0Before
    );
    assertEq(
      IERC20(Currency.unwrap(currency1)).balanceOf(surplusRecipient),
      claimAmount1 == 0 ? mintAmount1 : claimAmount1 + recipientAmount1Before
    );
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_claimSurplusNative_succeed(uint256 mintAmount, uint256 claimAmount)
    public
  {
    mintAmount = bound(mintAmount, 0, uint128(type(int128).max));
    claimAmount = bound(claimAmount, 0, mintAmount);
    vault.lock(abi.encode(mintAmount, type(uint256).max));

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = claimAmount == 0 ? mintAmount : claimAmount;

    uint256 recipientBalanceBefore = surplusRecipient.balance;

    vm.prank(operator);
    vm.expectEmit(true, true, true, true, hook);
    emit IELHook.ELHookClaimSurplusTokens(surplusRecipient, tokens, amounts);
    amounts[0] = claimAmount;
    IELHook(hook).claimSurplusTokens(tokens, amounts);

    assertEq(
      surplusRecipient.balance, claimAmount == 0 ? mintAmount : claimAmount + recipientBalanceBefore
    );
  }

  /// forge-config: default.fuzz.runs = 20
  function test_pancakeswap_claimSurplusTokens_notOperator_shouldFail(
    uint256 addressIndex,
    uint256 mintAmount0,
    uint256 mintAmount1,
    uint256 claimAmount0,
    uint256 claimAmount1
  ) public {
    mintAmount0 = bound(mintAmount0, 0, uint128(type(int128).max));
    mintAmount1 = bound(mintAmount1, 0, uint128(type(int128).max));
    claimAmount0 = bound(claimAmount0, 0, mintAmount0);
    claimAmount1 = bound(claimAmount1, 0, mintAmount1);
    vault.lock(abi.encode(mintAmount0, mintAmount1));

    address[] memory tokens = new address[](2);
    tokens[0] = Currency.unwrap(currency0);
    tokens[1] = Currency.unwrap(currency1);
    uint256[] memory amounts = new uint256[](2);

    address actor = actorAddresses[bound(addressIndex, 0, actorAddresses.length - 1)];
    vm.assume(actor != operator);
    vm.prank(actor);
    amounts[0] = claimAmount0;
    amounts[1] = claimAmount1;
    vm.expectRevert(abi.encodeWithSelector(KyberSwapRole.KSRoleNotOperator.selector, actor));
    IELHook(hook).claimSurplusTokens(tokens, amounts);
  }

  function lockAcquired(bytes calldata data) public returns (bytes memory) {
    (uint256 mintAmount0, uint256 mintAmount1) = abi.decode(data, (uint256, uint256));

    if (mintAmount1 == type(uint256).max) {
      Currency native = Currency.wrap(address(0));

      vault.mint(hook, native, mintAmount0);

      vault.sync(native);
      vault.settle{value: mintAmount0}();
    } else {
      vault.mint(hook, currency0, mintAmount0);
      vault.mint(hook, currency1, mintAmount1);

      vault.sync(currency0);
      IERC20(Currency.unwrap(currency0)).transfer(address(vault), mintAmount0);
      vault.settle();

      vault.sync(currency1);
      IERC20(Currency.unwrap(currency1)).transfer(address(vault), mintAmount1);
      vault.settle();
    }
  }
}
