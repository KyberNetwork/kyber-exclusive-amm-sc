// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseKEMHookV2Accounting} from './BaseKEMHookV2Accounting.sol';
import {BaseKEMHookV2State} from './BaseKEMHookV2State.sol';
import {PoolStateView} from './PoolStateView.sol';

import {KEMHookV2Library} from '../libraries/KEMHookV2Library.sol';

import {FixedPoint128} from 'uniswap/v4-core/src/libraries/FixedPoint128.sol';
import {FullMath} from 'uniswap/v4-core/src/libraries/FullMath.sol';
import {LiquidityMath} from 'uniswap/v4-core/src/libraries/LiquidityMath.sol';

abstract contract BaseKEMHookV2Subscriber is
  BaseKEMHookV2State,
  BaseKEMHookV2Accounting,
  PoolStateView
{
  using KEMHookV2Library for *;

  /// @notice Internal logic for `notifySubscribe`
  function _notifySubscribe(uint256 tokenId) internal {
    (bytes32 poolId, address token0, address token1, int24 tickLower, int24 tickUpper) =
      _getPoolAndPositionInfo(tokenId);
    uint128 liquidity = _getPositionLiquidity(tokenId, poolId, tickLower, tickUpper);

    _updatePositionEGInfo(tokenId, poolId, token0, token1, tickLower, tickUpper, int128(liquidity));
  }

  /// @notice Internal logic for `notifyUnsubscribe`
  function _notifyUnsubscribe(uint256 tokenId) internal {
    (bytes32 poolId, address token0, address token1, int24 tickLower, int24 tickUpper) =
      _getPoolAndPositionInfo(tokenId);
    uint128 liquidity = _getPositionLiquidity(tokenId, poolId, tickLower, tickUpper);

    _updatePositionEGInfo(tokenId, poolId, token0, token1, tickLower, tickUpper, -int128(liquidity));
  }

  /// @notice Internal logic for `notifyBurn`
  function _notifyBurn(
    uint256 tokenId,
    bytes32 poolId,
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    uint256 liquidity
  ) internal {
    _updatePositionEGInfo(
      tokenId, poolId, token0, token1, tickLower, tickUpper, -int128(int256(liquidity))
    );
  }

  /// @notice Internal logic for `notifyModifyLiquidity`
  function _notifyModifyLiquidity(uint256 tokenId, int256 liquidityDelta) internal {
    (bytes32 poolId, address token0, address token1, int24 tickLower, int24 tickUpper) =
      _getPoolAndPositionInfo(tokenId);
    _updatePositionEGInfo(
      tokenId, poolId, token0, token1, tickLower, tickUpper, int128(liquidityDelta)
    );
  }

  /// @notice Updates the position EG info after modifying liquidity
  /// @notice Returns the amount of EGs owed to the position owner
  function _updatePositionEGInfo(
    uint256 tokenId,
    bytes32 poolId,
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    int128 liquidityDelta
  ) internal {
    PoolEGState storage egState = pools[poolId];
    PositionEGInfo storage positionEGInfo = positionEGInfos[tokenId];
    int24 tickCurrent = _getSlot0Data(poolId).tick();

    (uint256 egGrowthInside0X128, uint256 egGrowthInside1X128) =
      _getEGGrowthInside(egState, tickCurrent, tickLower, tickUpper);

    uint128 liquidity = positionEGInfo.liquidity;
    // update liquidity
    positionEGInfo.liquidity = LiquidityMath.addDelta(liquidity, liquidityDelta);

    // calculate accumulated EGs. overflow in the subtraction of eg growth is expected
    unchecked {
      uint256 egOwed0 = FullMath.mulDiv(
        egGrowthInside0X128 - positionEGInfo.egGrowthInside0LastX128, liquidity, FixedPoint128.Q128
      );
      if (egOwed0 > 0) {
        _take(token0, address(this), egOwed0);
        _settle(token0, msg.sender, egOwed0);
      }

      uint256 egOwed1 = FullMath.mulDiv(
        egGrowthInside1X128 - positionEGInfo.egGrowthInside1LastX128, liquidity, FixedPoint128.Q128
      );
      if (egOwed1 > 0) {
        _take(token1, address(this), egOwed1);
        _settle(token1, msg.sender, egOwed1);
      }
    }

    // update last EG growth inside
    positionEGInfo.egGrowthInside0LastX128 = egGrowthInside0X128;
    positionEGInfo.egGrowthInside1LastX128 = egGrowthInside1X128;
  }

  /// @notice Returns the EG growth inside the position
  function _getEGGrowthInside(
    PoolEGState storage egState,
    int24 tickCurrent,
    int24 tickLower,
    int24 tickUpper
  ) internal view returns (uint256 egGrowthInside0X128, uint256 egGrowthInside1X128) {
    TickEGInfo storage lower = egState.ticks[tickLower];
    TickEGInfo storage upper = egState.ticks[tickUpper];

    unchecked {
      if (tickCurrent < tickLower) {
        egGrowthInside0X128 = lower.egGrowthOutside0X128 - upper.egGrowthOutside0X128;
        egGrowthInside1X128 = lower.egGrowthOutside1X128 - upper.egGrowthOutside1X128;
      } else if (tickCurrent >= tickUpper) {
        egGrowthInside0X128 = upper.egGrowthOutside0X128 - lower.egGrowthOutside0X128;
        egGrowthInside1X128 = upper.egGrowthOutside1X128 - lower.egGrowthOutside1X128;
      } else {
        egGrowthInside0X128 =
          egState.egGrowthGlobal0X128 - lower.egGrowthOutside0X128 - upper.egGrowthOutside0X128;
        egGrowthInside1X128 =
          egState.egGrowthGlobal1X128 - lower.egGrowthOutside1X128 - upper.egGrowthOutside1X128;
      }
    }
  }

  /// @notice Returns the pool and position info for a given tokenId
  function _getPoolAndPositionInfo(uint256 tokenId)
    internal
    view
    virtual
    returns (bytes32 poolId, address token0, address token1, int24 tickLower, int24 tickUpper);

  /// @notice Returns the liquidity for a given tokenId
  function _getPositionLiquidity(uint256 tokenId, bytes32 poolId, int24 tickLower, int24 tickUpper)
    internal
    view
    virtual
    returns (uint128 liquidity);
}
