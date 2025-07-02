// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FFHookAccounting} from './FFHookAccounting.sol';
import {FFHookStateView} from './FFHookStateView.sol';
import {FFHookStorage} from './FFHookStorage.sol';

import {PoolExt} from '../libraries/PoolExt.sol';

import {SafeCast} from 'uniswap/v4-core/src/libraries/SafeCast.sol';
import {BalanceDelta, toBalanceDelta} from 'uniswap/v4-core/src/types/BalanceDelta.sol';
import {Slot0, Slot0Library} from 'uniswap/v4-core/src/types/Slot0.sol';

abstract contract FFHookAfterModifyLiquidity is FFHookStorage, FFHookStateView, FFHookAccounting {
  using PoolExt for PoolExt.State;
  using Slot0Library for bytes32;
  using SafeCast for *;

  /// @notice Internal logic for `afterAddLiquidity` and `afterRemoveLiquidity`
  function _afterModifyLiquidity(
    bytes32 poolId,
    address token0,
    address token1,
    address owner,
    int24 tickLower,
    int24 tickUpper,
    bytes32 salt,
    int128 liquidityDelta
  ) internal returns (int256 hookDelta) {
    PoolExt.State storage pool = pools[poolId];

    (uint128 liquidityGrossAfterLower,) = _getTickLiquidity(poolId, tickLower);
    (uint128 liquidityGrossAfterUpper,) = _getTickLiquidity(poolId, tickUpper);

    PoolExt.AfterModifyLiquidityParams memory params = PoolExt.AfterModifyLiquidityParams({
      owner: owner,
      tickLower: tickLower,
      tickUpper: tickUpper,
      salt: salt,
      tickCurrent: Slot0.wrap(_getSlot0Data(poolId)).tick(),
      liquidityGrossAfterLower: liquidityGrossAfterLower,
      liquidityGrossAfterUpper: liquidityGrossAfterUpper,
      liquidityAfter: _getPositionLiquidity(poolId, owner, tickLower, tickUpper, salt),
      liquidityDelta: liquidityDelta
    });

    (uint256 egOwed0, uint256 egOwed1) = pool.afterModifyLiquidity(params);

    if (egOwed0 != 0) {
      _burn(token0, egOwed0);
    }
    if (egOwed1 != 0) {
      _burn(token1, egOwed1);
    }

    // the hook delta is negative because we are releasing EG
    hookDelta = BalanceDelta.unwrap(toBalanceDelta(-egOwed0.toInt128(), -egOwed1.toInt128()));
  }
}
