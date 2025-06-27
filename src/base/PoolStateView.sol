// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {KEMHookV2Library, PoolState} from '../libraries/KEMHookV2Library.sol';

import {BitMath} from 'uniswap/v4-core/src/libraries/BitMath.sol';
import {ProtocolFeeLibrary} from 'uniswap/v4-core/src/libraries/ProtocolFeeLibrary.sol';
import {TickBitmap} from 'uniswap/v4-core/src/libraries/TickBitmap.sol';

import {SlotDerivation} from 'openzeppelin-contracts/contracts/utils/SlotDerivation.sol';
import {TransientSlot} from 'openzeppelin-contracts/contracts/utils/TransientSlot.sol';

abstract contract PoolStateView {
  using TickBitmap for int24;
  using ProtocolFeeLibrary for *;
  using KEMHookV2Library for *;
  using TransientSlot for *;
  using SlotDerivation for bytes32;

  // bytes32 slot0DataStart;
  // uint128 liquidityStart;
  // uint256[] tickLiquidities;
  // uint256[] positiveEGAmounts;

  bytes32 internal constant SLOT0_DATA_START_SLOT = keccak256('SLOT0_DATA_START_SLOT');

  bytes32 internal constant LIQUIDITY_START_SLOT = keccak256('LIQUIDITY_START_SLOT');

  bytes32 internal constant TICK_LIQUIDITIES_SLOT = keccak256('TICK_LIQUIDITIES_SLOT');

  bytes32 internal constant POSITIVE_EG_AMOUNTS_SLOT = keccak256('POSITIVE_EG_AMOUNTS_SLOT');

  /// @notice Returns the slot0 data of a pool
  function _getSlot0Data(bytes32 poolId) internal view virtual returns (bytes32);

  /// @notice Returns the liquidity of a pool
  function _getLiquidity(bytes32 poolId) internal view virtual returns (uint128);

  /// @notice Returns the tick bitmap of a pool at a specific word
  function _getTickBitmap(bytes32 poolId, int16 word)
    internal
    view
    virtual
    returns (uint256 tickBitmap);

  /// @notice Returns the liquidity net of a pool at a specific tick
  function _getLiquidityNet(bytes32 poolId, int24 tick)
    internal
    view
    virtual
    returns (int128 liquidityNet);

  /// @notice  the next initialized tick contained in the same word (or adjacent word) as the tick that is either
  /// to the left (less than or equal to) or right (greater than) of the given tick
  /// @dev Original implementation: uniswap/v4-core/libraries/TickBitmap.sol:nextInitializedTickWithinOneWord
  function _nextInitializedTickWithinOneWord(
    bytes32 poolId,
    int24 tick,
    int24 tickSpacing,
    bool lte
  ) internal view returns (int24 next, bool initialized) {
    unchecked {
      int24 compressed = tick.compress(tickSpacing);

      if (lte) {
        (int16 wordPos, uint8 bitPos) = compressed.position();
        // all the 1s at or to the right of the current bitPos
        uint256 mask = type(uint256).max >> (uint256(type(uint8).max) - bitPos);
        uint256 masked = _getTickBitmap(poolId, wordPos) & mask;

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
        uint256 masked = _getTickBitmap(poolId, wordPos) & mask;

        // if there are no initialized ticks to the left of the current tick, return leftmost in the word
        initialized = masked != 0;
        // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
        next = initialized
          ? (compressed + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))) * tickSpacing
          : (compressed + int24(uint24(type(uint8).max - bitPos))) * tickSpacing;
      }
    }
  }

  /// @notice Stores the pool state before swap
  function _setPoolStateStart(bytes32 poolId) internal {
    SLOT0_DATA_START_SLOT.asBytes32().tstore(_getSlot0Data(poolId));
    LIQUIDITY_START_SLOT.asUint256().tstore(_getLiquidity(poolId));
  }

  /// @notice Returns the pool state before swap
  function _getPoolStateStart(bool zeroForOne) internal returns (PoolState memory poolState) {
    poolState = SLOT0_DATA_START_SLOT.asBytes32().tload().toPoolState(zeroForOne);
    SLOT0_DATA_START_SLOT.asBytes32().tstore(0);

    poolState.liquidity = uint128(LIQUIDITY_START_SLOT.asUint256().tload());
    LIQUIDITY_START_SLOT.asUint256().tstore(0);
  }

  function _setTickLiquidity(uint256 index, int24 tick, uint128 liquidity) internal {
    TICK_LIQUIDITIES_SLOT.offset(index).asUint256().tstore(
      KEMHookV2Library.toTickLiquidity(tick, liquidity)
    );
  }

  function _setPositiveEGAmount(uint256 index, uint256 positiveEGAmount) internal {
    POSITIVE_EG_AMOUNTS_SLOT.offset(index).asUint256().tstore(positiveEGAmount);
  }

  function _getTickLiquidity(uint256 index) internal returns (int24 tick, uint128 liquidity) {
    TransientSlot.Uint256Slot tickLiquiditySlot = TICK_LIQUIDITIES_SLOT.offset(index).asUint256();
    uint256 tickLiquidity = tickLiquiditySlot.tload();
    tickLiquiditySlot.tstore(0);

    (tick, liquidity) = KEMHookV2Library.unpackTickLiquidity(tickLiquidity);
  }

  function _getPositiveEGAmount(uint256 index) internal returns (uint256 positiveEGAmount) {
    TransientSlot.Uint256Slot positiveEGAmountSlot =
      POSITIVE_EG_AMOUNTS_SLOT.offset(index).asUint256();
    positiveEGAmount = positiveEGAmountSlot.tload();
    positiveEGAmountSlot.tstore(0);
  }
}
