// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPoint128} from 'uniswap/v4-core/src/libraries/FixedPoint128.sol';
import {FullMath} from 'uniswap/v4-core/src/libraries/FullMath.sol';
import {Position} from 'uniswap/v4-core/src/libraries/Position.sol';

/// @title PositionExt
/// @notice Contains functions for managing position EG information and relevant calculations
library PositionExt {
  using FullMath for uint256;

  /// @notice EG info stored for each user's position
  struct Info {
    /// @notice EG growth per unit of liquidity as of the last update to liquidity or EGs owed
    uint256 egGrowthInside0LastX128;
    uint256 egGrowthInside1LastX128;
  }

  /// @notice Returns the Info struct of a position, given an owner and position boundaries
  /// @param self The mapping containing all user positions
  /// @param owner The address of the position owner
  /// @param tickLower The lower tick boundary of the position
  /// @param tickUpper The upper tick boundary of the position
  /// @param salt A unique value to differentiate between multiple positions in the same range
  /// @return position The position info struct of the given owners' position
  function get(
    mapping(bytes32 => Info) storage self,
    address owner,
    int24 tickLower,
    int24 tickUpper,
    bytes32 salt
  ) internal view returns (Info storage position) {
    bytes32 positionKey = Position.calculatePositionKey(owner, tickLower, tickUpper, salt);
    position = self[positionKey];
  }

  /// @notice Credits accumulated EGs to a user's position
  /// @param self The individual position to update
  /// @param liquidityBefore The liquidity of the position before modification
  /// @param egGrowthInside0X128 The all-time EG growth in currency0, per unit of liquidity, inside the position's tick boundaries
  /// @param egGrowthInside1X128 The all-time EG growth in currency1, per unit of liquidity, inside the position's tick boundaries
  /// @return egOwed0 The amount of currency0 EG owed to the position owner
  /// @return egOwed1 The amount of currency1 EG owed to the position owner
  function update(
    Info storage self,
    uint128 liquidityBefore,
    uint256 egGrowthInside0X128,
    uint256 egGrowthInside1X128
  ) internal returns (uint256 egOwed0, uint256 egOwed1) {
    unchecked {
      egOwed0 = (egGrowthInside0X128 - self.egGrowthInside0LastX128).mulDiv(
        liquidityBefore, FixedPoint128.Q128
      );
      egOwed1 = (egGrowthInside1X128 - self.egGrowthInside1LastX128).mulDiv(
        liquidityBefore, FixedPoint128.Q128
      );

      // update the position
      self.egGrowthInside0LastX128 = egGrowthInside0X128;
      self.egGrowthInside1LastX128 = egGrowthInside1X128;
    }
  }
}
