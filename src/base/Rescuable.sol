// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRescuable} from '../interfaces/IRescuable.sol';

import {IERC1155} from 'openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol';
import {IERC20, SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';
import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';

abstract contract Rescuable is IRescuable {
  using SafeERC20 for IERC20;

  /// @inheritdoc IRescuable
  function rescueERC20s(
    IERC20[] calldata tokens,
    uint256[] memory amounts,
    address payable recipient
  ) external {
    _checkOwner();
    require(recipient != address(0), InvalidAddress());
    require(tokens.length == amounts.length, MismatchedArrayLengths());

    for (uint256 i = 0; i < tokens.length; i++) {
      amounts[i] = _transfer(tokens[i], amounts[i], recipient);
    }

    emit RescueERC20s(tokens, amounts, recipient);
  }

  /// @inheritdoc IRescuable
  function rescueERC721s(IERC721[] calldata tokens, uint256[] memory tokenIds, address recipient)
    external
  {
    _checkOwner();
    require(recipient != address(0), InvalidAddress());
    require(tokens.length == tokenIds.length, MismatchedArrayLengths());

    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i].safeTransferFrom(address(this), recipient, tokenIds[i]);
    }

    emit RescueERC721s(tokens, tokenIds, recipient);
  }

  /// @inheritdoc IRescuable
  function rescueERC1155s(
    IERC1155[] calldata tokens,
    uint256[] memory tokenIds,
    uint256[] memory amounts,
    address recipient
  ) external {
    _checkOwner();
    require(recipient != address(0), InvalidAddress());
    require(tokens.length == tokenIds.length, MismatchedArrayLengths());
    require(tokens.length == amounts.length, MismatchedArrayLengths());

    for (uint256 i = 0; i < tokens.length; i++) {
      if (amounts[i] == 0) {
        amounts[i] = tokens[i].balanceOf(address(this), tokenIds[i]);
      }
      if (amounts[i] > 0) {
        tokens[i].safeTransferFrom(address(this), recipient, tokenIds[i], amounts[i], '');
      }
    }

    emit RescueERC1155s(tokens, tokenIds, amounts, recipient);
  }

  function _transfer(IERC20 token, uint256 amount, address payable recipient)
    internal
    returns (uint256)
  {
    if (address(token) == address(0)) {
      if (amount == 0) {
        amount = address(this).balance;
      }
      if (amount > 0) {
        Address.sendValue(recipient, amount);
      }
    } else {
      if (amount == 0) {
        amount = token.balanceOf(address(this));
      }
      if (amount > 0) {
        token.safeTransfer(recipient, amount);
      }
    }

    return amount;
  }

  function _checkOwner() internal view virtual;
}
