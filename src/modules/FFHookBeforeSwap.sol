// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFFHookBeforeSwap} from '../interfaces/modules/IFFHookBeforeSwap.sol';

import {FFHookNonces} from './FFHookNonces.sol';
import {FFHookStateView} from './FFHookStateView.sol';
import {FFHookStorage} from './FFHookStorage.sol';

import {CalldataDecoderExt} from '../libraries/CalldataDecoderExt.sol';
import {SafeTransientStorageAccess} from '../libraries/SafeTransientStorageAccess.sol';

import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

/// @title FFHookBeforeSwap
/// @notice Before swap module for the FFHook contract
abstract contract FFHookBeforeSwap is
  IFFHookBeforeSwap,
  FFHookStorage,
  FFHookStateView,
  FFHookNonces
{
  using SafeTransientStorageAccess for bytes32;

  /// @notice Internal logic for `beforeSwap`
  function _beforeSwap(
    address sender,
    bytes32 poolId,
    bool zeroForOne,
    int256 amountSpecified,
    bytes calldata hookData
  ) internal {
    if (amountSpecified >= 0) {
      revert ExactOutDisabled();
    }

    (
      int256 maxAmountIn,
      uint256 inverseFairExchangeRate,
      uint256 nonce,
      uint256 expiryTime,
      bytes memory signature
    ) = CalldataDecoderExt.decodeHookData(hookData);

    if (block.timestamp > expiryTime) {
      revert ExpiredSignature(expiryTime, block.timestamp);
    }

    unchecked {
      if (-amountSpecified > maxAmountIn) {
        revert TooLargeAmountIn(maxAmountIn, -amountSpecified);
      }
    }

    _useUnorderedNonce(nonce);

    bytes32 hash = keccak256(
      abi.encode(
        sender, poolId, zeroForOne, maxAmountIn, inverseFairExchangeRate, nonce, expiryTime
      )
    );
    if (!SignatureChecker.isValidSignatureNow(quoteSigner, hash, signature)) {
      revert InvalidSignature();
    }

    SLOT0_DATA_BEFORE_SLOT.tstore(_getSlot0Data(poolId));
    LIQUIDITY_BEFORE_SLOT.tstore(_getLiquidity(poolId));
  }
}
