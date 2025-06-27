// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKEMHookV2Errors} from '../interfaces/IKEMHookV2Errors.sol';

import {BaseKEMHookV2State} from './BaseKEMHookV2State.sol';
import {PoolStateView} from './PoolStateView.sol';
import {UnorderedNonce} from './UnorderedNonce.sol';

import {KEMHookV2DataDecoder} from '../libraries/KEMHookV2DataDecoder.sol';

import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

abstract contract BaseKEMHookV2BeforeSwap is
  IKEMHookV2Errors,
  BaseKEMHookV2State,
  UnorderedNonce,
  PoolStateView
{
  /// @notice Internal logic for `beforeSwap`
  function _beforeSwap(
    address sender,
    bytes32 poolId,
    bool zeroForOne,
    int256 amountSpecified,
    bytes calldata hookData
  ) internal {
    require(amountSpecified < 0, ExactOutputDisabled());

    (
      int256 maxAmountIn,
      uint256 fairExchangeRate,
      uint256 nonce,
      uint256 expiryTime,
      bytes memory signature
    ) = KEMHookV2DataDecoder.decodeAllHookData(hookData);

    require(block.timestamp <= expiryTime, ExpiredSignature(expiryTime, block.timestamp));
    unchecked {
      require(-amountSpecified <= maxAmountIn, TooLargeAmountIn(maxAmountIn, -amountSpecified));
    }

    _useUnorderedNonce(nonce);

    bytes32 hash = keccak256(
      abi.encode(sender, poolId, zeroForOne, maxAmountIn, fairExchangeRate, nonce, expiryTime)
    );
    require(SignatureChecker.isValidSignatureNow(quoteSigner, hash, signature), InvalidSignature());

    _setPoolStateStart(poolId);
  }
}
