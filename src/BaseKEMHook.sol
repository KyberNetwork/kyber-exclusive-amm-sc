// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKEMHook} from './interfaces/IKEMHook.sol';

import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {IERC1155} from 'openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol';
import {IERC20, SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';
import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';

/**
 * @title BaseKEMHook
 * @notice Abstract contract containing common implementation for KEMHook contracts
 */
abstract contract BaseKEMHook is IKEMHook, Ownable {
  /// @inheritdoc IKEMHook
  mapping(address account => bool status) public claimable;

  /// @inheritdoc IKEMHook
  mapping(address account => bool status) public whitelisted;

  /// @inheritdoc IKEMHook
  address public quoteSigner;

  /// @inheritdoc IKEMHook
  address public egRecipient;

  constructor(
    address initialOwner,
    address[] memory initialClaimableAccounts,
    address[] memory initialWhitelistedAccounts,
    address initialQuoteSigner,
    address initialEgRecipient
  ) Ownable(initialOwner) {
    _updateClaimable(initialClaimableAccounts, true);
    _updateWhitelisted(initialWhitelistedAccounts, true);
    _updateQuoteSigner(initialQuoteSigner);
    _updateEgRecipient(initialEgRecipient);
  }

  /// @inheritdoc IKEMHook
  function updateClaimable(address[] calldata accounts, bool newStatus) public onlyOwner {
    _updateClaimable(accounts, newStatus);
  }

  /// @inheritdoc IKEMHook
  function updateWhitelisted(address[] calldata accounts, bool newStatus) public onlyOwner {
    _updateWhitelisted(accounts, newStatus);
  }

  /// @inheritdoc IKEMHook
  function updateQuoteSigner(address newSigner) public onlyOwner {
    _updateQuoteSigner(newSigner);
  }

  /// @inheritdoc IKEMHook
  function updateEgRecipient(address newRecipient) public onlyOwner {
    _updateEgRecipient(newRecipient);
  }

  /// @inheritdoc IKEMHook
  function rescueERC20s(
    IERC20[] calldata tokens,
    uint256[] memory amounts,
    address payable recipient
  ) external onlyOwner {
    require(recipient != address(0), InvalidAddress());
    require(tokens.length == amounts.length, MismatchedArrayLengths());

    for (uint256 i = 0; i < tokens.length; i++) {
      amounts[i] = _transfer(tokens[i], amounts[i], recipient);
    }

    emit RescueERC20s(tokens, amounts, recipient);
  }

  /// @inheritdoc IKEMHook
  function rescueERC721s(IERC721[] calldata tokens, uint256[] memory tokenIds, address recipient)
    external
    onlyOwner
  {
    require(recipient != address(0), InvalidAddress());
    require(tokens.length == tokenIds.length, MismatchedArrayLengths());

    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i].safeTransferFrom(address(this), recipient, tokenIds[i]);
    }

    emit RescueERC721s(tokens, tokenIds, recipient);
  }

  /// @inheritdoc IKEMHook
  function rescueERC1155s(
    IERC1155[] calldata tokens,
    uint256[] memory tokenIds,
    uint256[] memory amounts,
    address recipient
  ) external onlyOwner {
    require(recipient != address(0), InvalidAddress());
    require(tokens.length == tokenIds.length, MismatchedArrayLengths());
    require(tokens.length == amounts.length, MismatchedArrayLengths());

    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i].safeTransferFrom(address(this), recipient, tokenIds[i], amounts[i], '');
    }

    emit RescueERC1155s(tokens, tokenIds, amounts, recipient);
  }

  function _updateClaimable(address[] memory accounts, bool newStatus) internal {
    for (uint256 i = 0; i < accounts.length; i++) {
      claimable[accounts[i]] = newStatus;

      emit UpdateClaimable(accounts[i], newStatus);
    }
  }

  function _updateWhitelisted(address[] memory accounts, bool newStatus) internal {
    for (uint256 i = 0; i < accounts.length; i++) {
      whitelisted[accounts[i]] = newStatus;

      emit UpdateWhitelisted(accounts[i], newStatus);
    }
  }

  function _updateQuoteSigner(address newSigner) internal {
    require(newSigner != address(0), InvalidAddress());
    quoteSigner = newSigner;

    emit UpdateQuoteSigner(newSigner);
  }

  function _updateEgRecipient(address newRecipient) internal {
    require(newRecipient != address(0), InvalidAddress());
    egRecipient = newRecipient;

    emit UpdateEgRecipient(newRecipient);
  }

  function _transfer(IERC20 token, uint256 amount, address payable recipient)
    internal
    returns (uint256)
  {
    if (address(token) == address(0)) {
      if (amount == 0) {
        amount = address(this).balance;
      }
      Address.sendValue(recipient, amount);
    } else {
      if (amount == 0) {
        amount = token.balanceOf(address(this));
      }
      SafeERC20.safeTransfer(token, recipient, amount);
    }

    return amount;
  }
}
