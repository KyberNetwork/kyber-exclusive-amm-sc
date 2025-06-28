// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ICLPoolManager} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol';
import {CLPosition} from 'pancakeswap/infinity-core/src/pool-cl/libraries/CLPosition.sol';
import {PoolId} from 'pancakeswap/infinity-core/src/types/PoolId.sol';

/// @notice A helper library to provide state getters that use extsload
library StateLibrary {
  /// @notice index of pools mapping in the CLPoolManager
  bytes32 public constant POOLS_SLOT = bytes32(uint256(4));

  /// @notice index of TicksInfo mapping in CLPool.State: mapping(int24 => Tick.Info) ticks;
  uint256 public constant TICKS_OFFSET = 4;

  /// @notice index of Position.State mapping in CLPool.State: mapping(bytes32 => CLPosition.State) positions;
  uint256 public constant POSITIONS_OFFSET = 6;

  /**
   * @notice Retrieves the liquidity information of a pool at a specific tick.
   * @dev Corresponds to pools[poolId].ticks[tick].liquidityGross and pools[poolId].ticks[tick].liquidityNet. A more gas efficient version of getTickInfo
   * @param manager The pool manager contract.
   * @param poolId The ID of the pool.
   * @param tick The tick to retrieve liquidity for.
   * @return liquidityGross The total position liquidity that references this tick
   * @return liquidityNet The amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left)
   */
  function getTickLiquidity(ICLPoolManager manager, PoolId poolId, int24 tick)
    internal
    view
    returns (uint128 liquidityGross, int128 liquidityNet)
  {
    bytes32 slot = _getTickInfoSlot(poolId, tick);

    bytes32 value = manager.extsload(slot);
    assembly ("memory-safe") {
      liquidityNet := sar(128, value)
      liquidityGross := and(value, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    }
  }

  /**
   * @notice Retrieves the liquidity of a position.
   * @dev Corresponds to pools[poolId].positions[positionId].liquidity. More gas efficient for just retrieiving liquidity as compared to getPositionInfo
   * @param manager The pool manager contract.
   * @param poolId The ID of the pool.
   * @param positionId The ID of the position.
   * @return liquidity The liquidity of the position.
   */
  function getPositionLiquidity(ICLPoolManager manager, PoolId poolId, bytes32 positionId)
    internal
    view
    returns (uint128 liquidity)
  {
    bytes32 slot = _getPositionInfoSlot(poolId, positionId);
    liquidity = uint128(uint256(manager.extsload(slot)));
  }

  function _getPoolStateSlot(PoolId poolId) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
  }

  function _getTickInfoSlot(PoolId poolId, int24 tick) internal pure returns (bytes32) {
    // slot key of Pool.State value: `pools[poolId]`
    bytes32 stateSlot = _getPoolStateSlot(poolId);

    // Pool.State: `mapping(int24 => TickInfo) ticks`
    bytes32 ticksMappingSlot = bytes32(uint256(stateSlot) + TICKS_OFFSET);

    // slot key of the tick key: `pools[poolId].ticks[tick]
    return keccak256(abi.encodePacked(int256(tick), ticksMappingSlot));
  }

  function _getPositionInfoSlot(PoolId poolId, bytes32 positionId) internal pure returns (bytes32) {
    // slot key of Pool.State value: `pools[poolId]`
    bytes32 stateSlot = _getPoolStateSlot(poolId);

    // Pool.State: `mapping(bytes32 => Position.State) positions;`
    bytes32 positionMapping = bytes32(uint256(stateSlot) + POSITIONS_OFFSET);

    // slot of the mapping key: `pools[poolId].positions[positionId]
    return keccak256(abi.encodePacked(positionId, positionMapping));
  }
}
