// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKEMHookV2Events} from '../interfaces/IKEMHookV2Events.sol';

import {BaseKEMHookV2State} from './BaseKEMHookV2State.sol';
import {PoolStateView} from './PoolStateView.sol';

import {KEMHookV2DataDecoder} from '../libraries/KEMHookV2DataDecoder.sol';
import {KEMHookV2Library, PoolState} from '../libraries/KEMHookV2Library.sol';

import {FixedPoint128} from 'uniswap/v4-core/src/libraries/FixedPoint128.sol';
import {LiquidityMath} from 'uniswap/v4-core/src/libraries/LiquidityMath.sol';
import {SwapMath} from 'uniswap/v4-core/src/libraries/SwapMath.sol';
import {TickMath} from 'uniswap/v4-core/src/libraries/TickMath.sol';
import {UnsafeMath} from 'uniswap/v4-core/src/libraries/UnsafeMath.sol';

abstract contract BaseKEMHookV2AfterSwap is IKEMHookV2Events, BaseKEMHookV2State, PoolStateView {
  using KEMHookV2Library for *;
  using UnsafeMath for *;

  struct StepComputations {
    // the current sqrt price
    uint160 sqrtPriceCurrentX96;
    // the current tick
    int24 tickCurrent;
    // the current liquidity
    uint128 liquidity;
    // the sqrt price at the end of the swap
    uint160 sqrtPriceEndX96;
    // the positive EG amount for the current tick range
    uint256 positiveEGAmount;
    // the sum of the positive EG amounts for all tick ranges
    uint256 sumPositiveEGAmounts;
    // the number of tick ranges
    uint256 numTickRanges;
    // the global EG growth of the output token, updated in storage at the end of swap
    uint256 egGrowthGlobalX128;
  }

  /// @notice Internal logic for `afterSwap`
  function _afterSwap(
    bytes32 poolId,
    int24 tickSpacing,
    address tokenOut,
    bool zeroForOne,
    int256 delta,
    bytes calldata hookData
  ) internal returns (uint256 totalEGAmount) {
    uint256 fairExchangeRate = KEMHookV2DataDecoder.decodeFairExchangeRate(hookData);

    uint256 lpEGAmount;
    (totalEGAmount, lpEGAmount) =
      _calculateEGAmounts(poolId, tokenOut, zeroForOne, delta, fairExchangeRate);

    if (lpEGAmount > 0) {
      _updateTickEGInfos(poolId, tickSpacing, zeroForOne, fairExchangeRate, lpEGAmount);
    }
  }

  /// @notice Calculates the total, protocol, and LP EG amounts
  function _calculateEGAmounts(
    bytes32 poolId,
    address tokenOut,
    bool zeroForOne,
    int256 delta,
    uint256 fairExchangeRate
  ) internal returns (uint256 totalEGAmount, uint256 lpEGAmount) {
    unchecked {
      // unpack the delta into amountIn and amountOut
      uint256 amountIn;
      uint256 amountOut;
      if (zeroForOne) {
        (amountIn, amountOut) = delta.unpackDelta();
      } else {
        (amountOut, amountIn) = delta.unpackDelta();
      }
      amountIn = amountIn.negate();

      // calculate the fair amount out
      uint256 fairAmountOut = amountIn.simpleMulDiv(fairExchangeRate, EXCHANGE_RATE_DENOMINATOR);

      // calculate the total EG amount
      lpEGAmount = totalEGAmount = fairAmountOut < amountOut ? amountOut - fairAmountOut : 0;
      if (totalEGAmount > 0) {
        // calculate the protocol fee on the total EG amount
        uint256 protocolEGAmount =
          totalEGAmount.simpleMulDiv(pools[poolId].protocolEGFee, PIPS_DENOMINATOR);
        if (protocolEGAmount > 0) {
          lpEGAmount -= protocolEGAmount;
          protocolEGUnclaimed[tokenOut] += protocolEGAmount;
        }

        emit AbsorbEG(poolId, tokenOut, totalEGAmount);
      }
    }
  }

  /// @notice Updates the tick EG infos for the given pool
  function _updateTickEGInfos(
    bytes32 poolId,
    int24 tickSpacing,
    bool zeroForOne,
    uint256 fairExchangeRate,
    uint256 lpEGAmount
  ) internal {
    PoolState memory poolState = _getPoolStateStart(zeroForOne);

    StepComputations memory step;

    step.sqrtPriceCurrentX96 = poolState.sqrtPriceX96;
    step.tickCurrent = poolState.tick;
    step.liquidity = poolState.liquidity;

    step.sqrtPriceEndX96 = _getSlot0Data(poolId).sqrtPriceX96();

    while (true) {
      (int24 tickNext, bool initialized) =
        _nextInitializedTickWithinOneWord(poolId, step.tickCurrent, tickSpacing, zeroForOne);

      // get the sqrt price for the next tick
      uint160 sqrtPriceNextX96 = TickMath.getSqrtPriceAtTick(tickNext);
      // get the target sqrt price, as we are limited by the end sqrt price
      uint160 sqrtPriceTargetX96 =
        SwapMath.getSqrtPriceTarget(zeroForOne, sqrtPriceNextX96, step.sqrtPriceEndX96);

      // calculate the swap amounts
      (uint256 amountIn, uint256 amountOut) = KEMHookV2Library.calculateSwapAmounts(
        step.sqrtPriceCurrentX96, sqrtPriceTargetX96, step.liquidity, zeroForOne
      );
      // calculate the amount in plus fee
      uint256 amountInPlusFee =
        UnsafeMath.simpleMulDiv(amountIn, PIPS_DENOMINATOR, PIPS_DENOMINATOR - poolState.swapFee);

      // calculate the fair amount out
      uint256 fairAmountOut =
        amountInPlusFee.simpleMulDiv(fairExchangeRate, EXCHANGE_RATE_DENOMINATOR);
      if (step.positiveEGAmount + amountOut > fairAmountOut) {
        unchecked {
          step.positiveEGAmount = step.positiveEGAmount + amountOut - fairAmountOut;
        }
      } else {
        break;
      }

      // if we reached the next tick, store the tick liquidity and positive EG amount
      if (initialized && sqrtPriceTargetX96 == sqrtPriceNextX96) {
        _setTickLiquidity(step.numTickRanges, tickNext, step.liquidity);
        _setPositiveEGAmount(step.numTickRanges, step.positiveEGAmount);

        step.numTickRanges++;
        step.sumPositiveEGAmounts += step.positiveEGAmount;
        step.positiveEGAmount = 0;
      }

      // if we reached the end sqrt price, break
      if (sqrtPriceTargetX96 == step.sqrtPriceEndX96) {
        break;
      }

      // update the current tick and sqrt price
      unchecked {
        if (initialized) {
          int128 liquidityNet = _getLiquidityNet(poolId, step.tickCurrent);
          step.liquidity =
            LiquidityMath.addDelta(step.liquidity, zeroForOne ? -liquidityNet : liquidityNet);
        }

        step.tickCurrent = zeroForOne ? tickNext - 1 : tickNext;
        step.sqrtPriceCurrentX96 = sqrtPriceNextX96;
      }
    }

    PoolEGState storage egState = pools[poolId];

    step.egGrowthGlobalX128 = zeroForOne ? egState.egGrowthGlobal1X128 : egState.egGrowthGlobal0X128;

    for (uint256 index = 0; index < step.numTickRanges; index++) {
      (int24 tickNext, uint128 liquidity) = _getTickLiquidity(index);
      uint256 positiveEGAmount = _getPositiveEGAmount(index);

      // scale the positive EG amount to the LP EG amount
      uint256 scaledEGAmount = positiveEGAmount.simpleMulDiv(lpEGAmount, step.sumPositiveEGAmounts);
      // add the scaled EG amount to the global EG growth
      step.egGrowthGlobalX128 +=
        UnsafeMath.simpleMulDiv(scaledEGAmount, FixedPoint128.Q128, liquidity);

      // update the tick EG growth
      TickEGInfo storage tickEGInfo = egState.ticks[tickNext];
      if (zeroForOne) {
        tickEGInfo.egGrowthOutside1X128 = step.egGrowthGlobalX128 - tickEGInfo.egGrowthOutside1X128;
      } else {
        tickEGInfo.egGrowthOutside0X128 = step.egGrowthGlobalX128 - tickEGInfo.egGrowthOutside0X128;
      }
    }

    // update the global EG growth in storage
    if (zeroForOne) {
      egState.egGrowthGlobal1X128 = step.egGrowthGlobalX128;
    } else {
      egState.egGrowthGlobal0X128 = step.egGrowthGlobalX128;
    }
  }
}
