// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUnorderedNonce} from '../interfaces/IUnorderedNonce.sol';

/**
 * @title Unordered Nonce
 * @notice Contract state and methods for using unordered nonces in signatures
 */
contract UnorderedNonce is IUnorderedNonce {
  /// @inheritdoc IUnorderedNonce
  mapping(uint256 word => uint256 bitmap) public nonces;

  /// @notice Consume a nonce, reverting if it has already been used
  /// @param nonce uint256, the nonce to consume. The top 248 bits are the word, the bottom 8 bits indicate the bit position
  function _useUnorderedNonce(uint256 nonce) internal {
    // ignore nonce 0 for flexibility
    if (nonce == 0) return;

    uint256 wordPos = nonce >> 8;
    uint256 bitPos = uint8(nonce);

    uint256 bit = 1 << bitPos;
    uint256 flipped = nonces[wordPos] ^= bit;
    if (flipped & bit == 0) revert NonceAlreadyUsed(nonce);

    emit UseNonce(nonce);
  }
}
