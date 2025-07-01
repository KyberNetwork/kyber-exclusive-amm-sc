// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// import './Base.t.sol';

// contract UniswapHookClaimEGTest is UniswapHookBaseTest {
//   /// forge-config: default.fuzz.runs = 20
//   function test_uniswap_claimEGTokens_succeed(
//     uint256 mintAmount0,
//     uint256 mintAmount1,
//     uint256 claimAmount0,
//     uint256 claimAmount1
//   ) public {
//     mintAmount0 = bound(mintAmount0, 0, uint128(type(int128).max));
//     mintAmount1 = bound(mintAmount1, 0, uint128(type(int128).max));
//     claimAmount0 = bound(claimAmount0, 0, mintAmount0);
//     claimAmount1 = bound(claimAmount1, 0, mintAmount1);
//     manager.unlock(abi.encode(mintAmount0, mintAmount1));

//     address[] memory tokens = new address[](2);
//     tokens[0] = Currency.unwrap(currency0);
//     tokens[1] = Currency.unwrap(currency1);
//     uint256[] memory amounts = new uint256[](2);
//     amounts[0] = claimAmount0 == 0 ? mintAmount0 : claimAmount0;
//     amounts[1] = claimAmount1 == 0 ? mintAmount1 : claimAmount1;

//     uint256 recipientAmount0Before = IERC20(Currency.unwrap(currency0)).balanceOf(egRecipient);
//     uint256 recipientAmount1Before = IERC20(Currency.unwrap(currency1)).balanceOf(egRecipient);

//     vm.prank(operator);
//     vm.expectEmit(true, true, true, true, address(hook));
//     emit IKEMHook.ClaimEGTokens(egRecipient, tokens, amounts);
//     amounts[0] = claimAmount0;
//     amounts[1] = claimAmount1;
//     hook.claimEGTokens(tokens, amounts);

//     assertEq(
//       IERC20(Currency.unwrap(currency0)).balanceOf(egRecipient),
//       claimAmount0 == 0 ? mintAmount0 : claimAmount0 + recipientAmount0Before
//     );
//     assertEq(
//       IERC20(Currency.unwrap(currency1)).balanceOf(egRecipient),
//       claimAmount1 == 0 ? mintAmount1 : claimAmount1 + recipientAmount1Before
//     );
//   }

//   /// forge-config: default.fuzz.runs = 20
//   function test_uniswap_claimEGNative_succeed(uint256 mintAmount, uint256 claimAmount) public {
//     mintAmount = bound(mintAmount, 0, uint128(type(int128).max));
//     claimAmount = bound(claimAmount, 0, mintAmount);
//     manager.unlock(abi.encode(mintAmount, type(uint256).max));

//     address[] memory tokens = new address[](1);
//     tokens[0] = address(0);
//     uint256[] memory amounts = new uint256[](1);
//     amounts[0] = claimAmount == 0 ? mintAmount : claimAmount;

//     uint256 recipientBalanceBefore = egRecipient.balance;

//     vm.prank(operator);
//     vm.expectEmit(true, true, true, true, address(hook));
//     emit IKEMHook.ClaimEGTokens(egRecipient, tokens, amounts);
//     amounts[0] = claimAmount;
//     hook.claimEGTokens(tokens, amounts);

//     assertEq(
//       egRecipient.balance, claimAmount == 0 ? mintAmount : claimAmount + recipientBalanceBefore
//     );
//   }

//   /// forge-config: default.fuzz.runs = 20
//   function test_uniswap_claimEGTokens_withoutClaimRole_shouldFail(
//     uint256 actorIndex,
//     uint256 mintAmount0,
//     uint256 mintAmount1,
//     uint256 claimAmount0,
//     uint256 claimAmount1
//   ) public {
//     mintAmount0 = bound(mintAmount0, 0, uint128(type(int128).max));
//     mintAmount1 = bound(mintAmount1, 0, uint128(type(int128).max));
//     claimAmount0 = bound(claimAmount0, 0, mintAmount0);
//     claimAmount1 = bound(claimAmount1, 0, mintAmount1);
//     manager.unlock(abi.encode(mintAmount0, mintAmount1));

//     address[] memory tokens = new address[](2);
//     tokens[0] = Currency.unwrap(currency0);
//     tokens[1] = Currency.unwrap(currency1);
//     uint256[] memory amounts = new uint256[](2);

//     address actor = actors[bound(actorIndex, 0, actors.length - 1)];
//     vm.assume(actor != operator);
//     vm.prank(actor);
//     amounts[0] = claimAmount0;
//     amounts[1] = claimAmount1;
//     vm.expectRevert(abi.encodeWithSelector(IKEMHook.NonClaimableAccount.selector, actor));
//     hook.claimEGTokens(tokens, amounts);
//   }

//   function unlockCallback(bytes calldata data) public returns (bytes memory) {
//     (uint256 mintAmount0, uint256 mintAmount1) = abi.decode(data, (uint256, uint256));

//     if (mintAmount1 == type(uint256).max) {
//       Currency native = Currency.wrap(address(0));

//       manager.mint(address(hook), 0, mintAmount0);

//       manager.sync(native);
//       manager.settle{value: mintAmount0}();
//     } else {
//       manager.mint(address(hook), uint256(uint160(Currency.unwrap(currency0))), mintAmount0);
//       manager.mint(address(hook), uint256(uint160(Currency.unwrap(currency1))), mintAmount1);

//       manager.sync(currency0);
//       IERC20(Currency.unwrap(currency0)).transfer(address(manager), mintAmount0);
//       manager.settle();

//       manager.sync(currency1);
//       IERC20(Currency.unwrap(currency1)).transfer(address(manager), mintAmount1);
//       manager.settle();
//     }
//   }
// }
