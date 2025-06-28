// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LiquidityMath} from 'uniswap/v4-core/src/libraries/LiquidityMath.sol';

/// @title TickExt
/// @notice Contains functions for managing tick EG information and relevant calculations
library TickExt {
  /// @notice EG info stored for each initialized individual tick
  struct Info {
    // EG growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    // only has relative meaning, not absolute — the value depends on when the tick is initialized
    uint256 egGrowthOutside0X128;
    uint256 egGrowthOutside1X128;
  }

  /// @notice Retrieves fee growth data
  /// @param self The mapping containing all EG information for initialized ticks
  /// @param tickLower The lower tick boundary of the position
  /// @param tickUpper The upper tick boundary of the position
  /// @param tickCurrent The current tick
  /// @param egGrowthGlobal0X128 The all-time global EG growth, per unit of liquidity, in token0
  /// @param egGrowthGlobal1X128 The all-time global EG growth, per unit of liquidity, in token1
  /// @return egGrowthInside0X128 The all-time EG growth in token0, per unit of liquidity, inside the position's tick boundaries
  /// @return egGrowthInside1X128 The all-time EG growth in token1, per unit of liquidity, inside the position's tick boundaries
  function getEGGrowthInside(
    mapping(int24 => Info) storage self,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent,
    uint256 egGrowthGlobal0X128,
    uint256 egGrowthGlobal1X128
  ) internal view returns (uint256 egGrowthInside0X128, uint256 egGrowthInside1X128) {
    Info storage lower = self[tickLower];
    Info storage upper = self[tickUpper];

    // calculate EG growth below
    uint256 egGrowthBelow0X128;
    uint256 egGrowthBelow1X128;
    unchecked {
      if (tickCurrent >= tickLower) {
        egGrowthBelow0X128 = lower.egGrowthOutside0X128;
        egGrowthBelow1X128 = lower.egGrowthOutside1X128;
      } else {
        egGrowthBelow0X128 = egGrowthGlobal0X128 - lower.egGrowthOutside0X128;
        egGrowthBelow1X128 = egGrowthGlobal1X128 - lower.egGrowthOutside1X128;
      }

      // calculate EG growth above
      uint256 egGrowthAbove0X128;
      uint256 egGrowthAbove1X128;
      if (tickCurrent < tickUpper) {
        egGrowthAbove0X128 = upper.egGrowthOutside0X128;
        egGrowthAbove1X128 = upper.egGrowthOutside1X128;
      } else {
        egGrowthAbove0X128 = egGrowthGlobal0X128 - upper.egGrowthOutside0X128;
        egGrowthAbove1X128 = egGrowthGlobal1X128 - upper.egGrowthOutside1X128;
      }

      egGrowthInside0X128 = egGrowthGlobal0X128 - egGrowthBelow0X128 - egGrowthAbove0X128;
      egGrowthInside1X128 = egGrowthGlobal1X128 - egGrowthBelow1X128 - egGrowthAbove1X128;
    }
  }

  /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
  /// @param self The mapping containing all EG information for initialized ticks
  /// @param tick The tick that will be updated
  /// @param tickCurrent The current tick
  /// @param liquidityGrossAfter The liquidity after the modification
  /// @param liquidityDelta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
  /// @param egGrowthGlobal0X128 The all-time global EG growth, per unit of liquidity, in token0
  /// @param egGrowthGlobal1X128 The all-time global EG growth, per unit of liquidity, in token1
  /// @return flipped Whether the tick was flipped from initialized to uninitialized, or vice versa
  function update(
    mapping(int24 => Info) storage self,
    int24 tick,
    int24 tickCurrent,
    uint128 liquidityGrossAfter,
    int128 liquidityDelta,
    uint256 egGrowthGlobal0X128,
    uint256 egGrowthGlobal1X128
  ) internal returns (bool flipped) {
    uint128 liquidityGrossBefore = LiquidityMath.addDelta(liquidityGrossAfter, -liquidityDelta);

    flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

    if (liquidityGrossBefore == 0) {
      if (tick <= tickCurrent) {
        self[tick].egGrowthOutside0X128 = egGrowthGlobal0X128;
        self[tick].egGrowthOutside1X128 = egGrowthGlobal1X128;
      }
    }
  }

  /// @notice Clears EG info for a tick
  /// @param self The mapping containing all EG information for initialized ticks
  /// @param tick The tick that will be cleared
  function clear(mapping(int24 => Info) storage self, int24 tick) internal {
    delete self[tick];
  }

  /// @notice Transitions to next tick as needed by price movement
  /// @param self The mapping containing all EG information for initialized ticks
  /// @param tick The destination tick of the transition
  /// @param egGrowthGlobal0X128 The all-time global EG growth, per unit of liquidity, in token0
  /// @param egGrowthGlobal1X128 The all-time global EG growth, per unit of liquidity, in token1
  function cross(
    mapping(int24 => Info) storage self,
    int24 tick,
    uint256 egGrowthGlobal0X128,
    uint256 egGrowthGlobal1X128
  ) internal {
    unchecked {
      Info storage info = self[tick];
      info.egGrowthOutside0X128 = egGrowthGlobal0X128 - info.egGrowthOutside0X128;
      info.egGrowthOutside1X128 = egGrowthGlobal1X128 - info.egGrowthOutside1X128;
    }
  }
}
