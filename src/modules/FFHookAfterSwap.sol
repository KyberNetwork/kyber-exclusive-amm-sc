// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFFHookAfterSwap} from '../interfaces/modules/IFFHookAfterSwap.sol';

import {FFHookAccounting} from './FFHookAccounting.sol';
import {FFHookStateView} from './FFHookStateView.sol';
import {FFHookStorage} from './FFHookStorage.sol';

import {PoolExt} from '../libraries/PoolExt.sol';

import {CalldataDecoderExt} from '../libraries/CalldataDecoderExt.sol';
import {SafeTransientStorageAccess} from '../libraries/SafeTransientStorageAccess.sol';
import {Slot0, Slot0Library} from 'uniswap/v4-core/src/types/Slot0.sol';

abstract contract FFHookAfterSwap is
  IFFHookAfterSwap,
  FFHookStorage,
  FFHookStateView,
  FFHookAccounting
{
  using PoolExt for PoolExt.State;
  using Slot0Library for bytes32;
  using SafeTransientStorageAccess for bytes32;
  using CalldataDecoderExt for bytes;

  /// @notice Internal logic for `afterSwap`
  function _afterSwap(
    bytes32 poolId,
    int24 tickSpacing,
    address tokenOut,
    bool zeroForOne,
    int256 delta,
    bytes calldata hookData
  ) internal returns (uint256 totalEGAmount) {
    PoolExt.State storage pool = pools[poolId];

    Slot0 slot0DataBefore = Slot0.wrap(SLOT0_DATA_BEFORE_SLOT.tloadBytes32());

    PoolExt.AfterSwapParams memory params = PoolExt.AfterSwapParams({
      poolId: poolId,
      tickSpacing: tickSpacing,
      zeroForOne: zeroForOne,
      delta: delta,
      fairExchangeRate: hookData.fairExchangeRate(),
      sqrtPriceBeforeX96: slot0DataBefore.sqrtPriceX96(),
      tickBefore: slot0DataBefore.tick(),
      liquidityBefore: LIQUIDITY_BEFORE_SLOT.tloadUint128(),
      sqrtPriceAfterX96: Slot0.wrap(_getSlot0Data(poolId)).sqrtPriceX96(),
      protocolFee: slot0DataBefore.protocolFee(),
      lpFee: slot0DataBefore.lpFee(),
      protocolEGFee: pool.protocolEGFee
    });

    uint256 protocolEGAmount;
    (totalEGAmount, protocolEGAmount) = pool.afterSwap(params, _getTickBitmap, _getTickLiquidity);

    _mint(tokenOut, totalEGAmount);
    if (protocolEGAmount > 0) {
      protocolEGUnclaimed[tokenOut] += protocolEGAmount;
    }

    emit AbsorbEG(poolId, tokenOut, totalEGAmount);
  }
}
