// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BitMath} from 'uniswap/v4-core/src/libraries/BitMath.sol';
import {TickBitmap} from 'uniswap/v4-core/src/libraries/TickBitmap.sol';

library TickBitmapExt {
  using TickBitmap for int24;

  /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is either
  /// to the left (less than or equal to) or right (greater than) of the given tick
  /// @param poolId The pool id
  /// @param tick The starting tick
  /// @param tickSpacing The spacing between usable ticks
  /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
  /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
  /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
  /// @dev Based on `uniswap/v4-core/libraries/TickBitmap.sol:nextInitializedTickWithinOneWord`
  function nextInitializedTickWithinOneWord(
    bytes32 poolId,
    int24 tick,
    int24 tickSpacing,
    bool lte,
    function(bytes32, int16) view returns (uint256) getTickBitmap
  ) internal view returns (int24 next, bool initialized) {
    unchecked {
      int24 compressed = tick.compress(tickSpacing);

      if (lte) {
        (int16 wordPos, uint8 bitPos) = compressed.position();
        // all the 1s at or to the right of the current bitPos
        uint256 mask = type(uint256).max >> (uint256(type(uint8).max) - bitPos);
        uint256 masked = getTickBitmap(poolId, wordPos) & mask;

        // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
        initialized = masked != 0;
        // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
        next = initialized
          ? (compressed - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))) * tickSpacing
          : (compressed - int24(uint24(bitPos))) * tickSpacing;
      } else {
        // start from the word of the next tick, since the current tick state doesn't matter
        (int16 wordPos, uint8 bitPos) = (++compressed).position();
        // all the 1s at or to the left of the bitPos
        uint256 mask = ~((1 << bitPos) - 1);
        uint256 masked = getTickBitmap(poolId, wordPos) & mask;

        // if there are no initialized ticks to the left of the current tick, return leftmost in the word
        initialized = masked != 0;
        // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
        next = initialized
          ? (compressed + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))) * tickSpacing
          : (compressed + int24(uint24(type(uint8).max - bitPos))) * tickSpacing;
      }
    }
  }
}
