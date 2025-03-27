// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'src/UniswapV4ELHook.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {UniswapV4ELHookBaseTest} from 'test/uniswapV4ELHook/Base.t.sol';

contract UniswapV4ELHookClaimSurplusTest is UniswapV4ELHookBaseTest {
  function test_claimSurplusTokens_succeed(
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

  function test_claimSurplusTokens_notOperator_shouldFail(
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
    manager.unlock(abi.encode(mintAmount0, mintAmount1));

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
}
