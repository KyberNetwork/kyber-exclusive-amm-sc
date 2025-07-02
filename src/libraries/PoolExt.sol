// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MathExt} from './MathExt.sol';
import {PositionExt} from './PositionExt.sol';
import {TickBitmapExt} from './TickBitMapExt.sol';
import {TickExt} from './TickExt.sol';

import {SafeTransientStorageAccess} from './SafeTransientStorageAccess.sol';
import {FixedPoint128} from 'uniswap/v4-core/src/libraries/FixedPoint128.sol';
import {LiquidityMath} from 'uniswap/v4-core/src/libraries/LiquidityMath.sol';
import {SwapMath} from 'uniswap/v4-core/src/libraries/SwapMath.sol';
import {TickMath} from 'uniswap/v4-core/src/libraries/TickMath.sol';
import {UnsafeMath} from 'uniswap/v4-core/src/libraries/UnsafeMath.sol';

import {SlotDerivation} from 'openzeppelin-contracts/contracts/utils/SlotDerivation.sol';

/// @title PoolExt
/// @notice Contains functions for managing pool EG information and relevant calculations
library PoolExt {
  using TickExt for mapping(int24 => TickExt.Info);
  using PositionExt for mapping(bytes32 => PositionExt.Info);
  using PositionExt for PositionExt.Info;
  using UnsafeMath for uint256;
  using SafeTransientStorageAccess for bytes32;
  using SlotDerivation for bytes32;

  /// @notice The starting slot for the array of tick-liquidity pairs
  bytes32 constant TICK_LIQUIDITY_PAIRS_SLOT = keccak256('tickLiquidityPairs.slot');

  /// @notice The starting slot for the array of range EG amounts
  bytes32 constant RANGE_EG_AMOUNTS_SLOT = keccak256('rangeEGAmounts.slot');

  /// @notice The EG state of a pool
  struct State {
    uint24 protocolEGFee;
    uint256 egGrowthGlobal0X128;
    uint256 egGrowthGlobal1X128;
    mapping(int24 tick => TickExt.Info) ticks;
    mapping(bytes32 positionKey => PositionExt.Info) positions;
  }

  struct AfterModifyLiquidityParams {
    // the address that owns the position
    address owner;
    // the lower and upper tick of the position
    int24 tickLower;
    int24 tickUpper;
    // used to distinguish positions of the same owner, at the same tick range
    bytes32 salt;
    // the current tick
    int24 tickCurrent;
    // the liquidity gross after the modification
    uint128 liquidityGrossAfterLower;
    uint128 liquidityGrossAfterUpper;
    // the liquidity after the modification
    uint128 liquidityAfter;
    // any change in liquidity
    int128 liquidityDelta;
  }

  function afterModifyLiquidity(State storage self, AfterModifyLiquidityParams memory params)
    internal
    returns (uint256 egOwed0, uint256 egOwed1)
  {
    int24 tickLower = params.tickLower;
    int24 tickUpper = params.tickUpper;
    int24 tickCurrent = params.tickCurrent;
    int128 liquidityDelta = params.liquidityDelta;

    uint256 egGrowthGlobal0X128 = self.egGrowthGlobal0X128;
    uint256 egGrowthGlobal1X128 = self.egGrowthGlobal1X128;

    bool flippedLower = updateTick(
      self,
      tickLower,
      tickCurrent,
      params.liquidityGrossAfterLower,
      liquidityDelta,
      egGrowthGlobal0X128,
      egGrowthGlobal1X128
    );
    bool flippedUpper = updateTick(
      self,
      tickUpper,
      tickCurrent,
      params.liquidityGrossAfterUpper,
      liquidityDelta,
      egGrowthGlobal0X128,
      egGrowthGlobal1X128
    );

    (egOwed0, egOwed1) = updatePosition(
      self,
      params.owner,
      tickLower,
      tickUpper,
      params.salt,
      tickCurrent,
      params.liquidityAfter,
      liquidityDelta,
      egGrowthGlobal0X128,
      egGrowthGlobal1X128
    );

    if (liquidityDelta < 0) {
      if (flippedLower) {
        self.ticks.clear(tickLower);
      }
      if (flippedUpper) {
        self.ticks.clear(tickUpper);
      }
    }
  }

  function updateTick(
    State storage self,
    int24 tick,
    int24 tickCurrent,
    uint128 liquidityGrossAfter,
    int128 liquidityDelta,
    uint256 egGrowthGlobal0X128,
    uint256 egGrowthGlobal1X128
  ) internal returns (bool flipped) {
    flipped = self.ticks.update(
      tick,
      tickCurrent,
      liquidityGrossAfter,
      liquidityDelta,
      egGrowthGlobal0X128,
      egGrowthGlobal1X128
    );
  }

  function updatePosition(
    State storage self,
    address owner,
    int24 tickLower,
    int24 tickUpper,
    bytes32 salt,
    int24 tickCurrent,
    uint128 liquidityAfter,
    int128 liquidityDelta,
    uint256 egGrowthGlobal0X128,
    uint256 egGrowthGlobal1X128
  ) internal returns (uint256 egOwed0, uint256 egOwed1) {
    (uint256 egGrowthInside0X128, uint256 egGrowthInside1X128) = self.ticks.getEGGrowthInside(
      tickLower, tickUpper, tickCurrent, egGrowthGlobal0X128, egGrowthGlobal1X128
    );

    PositionExt.Info storage position = self.positions.get(owner, tickLower, tickUpper, salt);
    (egOwed0, egOwed1) = position.update(
      LiquidityMath.addDelta(liquidityAfter, -liquidityDelta),
      egGrowthInside0X128,
      egGrowthInside1X128
    );
  }

  struct AfterSwapParams {
    // the pool id
    bytes32 poolId;
    // the tick spacing
    int24 tickSpacing;
    // the direction of the swap
    bool zeroForOne;
    // the delta of the swap
    int256 delta;
    // the inverse fair exchange rate
    uint256 inverseFairExchangeRate;
    // the price before the swap
    uint160 sqrtPriceBeforeX96;
    // the tick before the swap
    int24 tickBefore;
    // the liquidity before the swap
    uint128 liquidityBefore;
    // the price after the swap
    uint160 sqrtPriceAfterX96;
    // the protocol fee
    uint24 protocolFee;
    // the lp fee
    uint24 lpFee;
    // the protocol EG fee
    uint24 protocolEGFee;
  }

  struct SwapState {
    uint24 swapFee;
    uint160 sqrtPriceX96;
    int24 tick;
    uint128 liquidity;
    // the amount in plus fee of the current range
    uint256 rangeAmountInPlusFee;
    // the amount out of the current range
    uint256 rangeAmountOut;
    // the number of initialized ticks
    uint256 numInitializedTicks;
    // the sum of the EG amounts over all ranges
    uint256 sumRangeEGAmounts;
  }

  function afterSwap(
    State storage self,
    AfterSwapParams memory params,
    function(bytes32, int16) internal view returns (uint256) getTickBitmap,
    function(bytes32, int24) internal view returns (uint128, int128) getTickLiquidity
  ) internal returns (uint256 totalEGAmount, uint256 protocolEGAmount) {
    totalEGAmount =
      MathExt.calculateEGAmount(params.delta, params.zeroForOne, params.inverseFairExchangeRate);

    /// @dev can't overflow
    protocolEGAmount = totalEGAmount.simpleMulDiv(params.protocolEGFee, MathExt.PIPS_DENOMINATOR);

    SwapState memory swapState = SwapState({
      sqrtPriceX96: params.sqrtPriceBeforeX96,
      tick: params.tickBefore,
      liquidity: params.liquidityBefore,
      rangeAmountInPlusFee: 0,
      rangeAmountOut: 0,
      sumRangeEGAmounts: 0,
      numInitializedTicks: 0,
      swapFee: MathExt.calculateSwapFee(params.protocolFee, params.lpFee, params.zeroForOne)
    });

    uint256 lastRangeEGAmount = calculateRangeEGAmounts(
      params.poolId,
      params.tickSpacing,
      params.zeroForOne,
      params.inverseFairExchangeRate,
      params.sqrtPriceAfterX96,
      swapState,
      getTickBitmap,
      getTickLiquidity
    );

    updateTicks(
      self, params.zeroForOne, totalEGAmount - protocolEGAmount, swapState, lastRangeEGAmount
    );
  }

  /// @notice Calculates the EG amounts generated by each initialized tick range
  /// @dev The results are stored in transient storage
  function calculateRangeEGAmounts(
    bytes32 poolId,
    int24 tickSpacing,
    bool zeroForOne,
    uint256 inverseFairExchangeRate,
    uint160 sqrtPriceAfterX96,
    SwapState memory swapState,
    function(bytes32, int16) view returns (uint256) getTickBitmap,
    function(bytes32, int24) view returns (uint128, int128) getTickLiquidity
  ) internal returns (uint256 lastRangeEGAmount) {
    while (true) {
      (int24 tickNext, bool initialized) = TickBitmapExt.nextInitializedTickWithinOneWord(
        poolId, swapState.tick, tickSpacing, zeroForOne, getTickBitmap
      );

      // ensure that we do not overshoot the min/max tick
      if (tickNext <= TickMath.MIN_TICK) {
        tickNext = TickMath.MIN_TICK;
      }
      if (tickNext >= TickMath.MAX_TICK) {
        tickNext = TickMath.MAX_TICK;
      }

      // get the price for the next tick
      uint160 sqrtPriceNextX96 = TickMath.getSqrtPriceAtTick(tickNext);
      // limit the target price by the price after the swap
      uint160 sqrtPriceTargetX96 =
        SwapMath.getSqrtPriceTarget(zeroForOne, sqrtPriceNextX96, sqrtPriceAfterX96);

      {
        // calculate the swap amounts
        (uint256 amountInPlusFee, uint256 amountOut) = MathExt.calculateSwapAmounts(
          swapState.sqrtPriceX96,
          sqrtPriceTargetX96,
          swapState.liquidity,
          zeroForOne,
          swapState.swapFee
        );

        swapState.rangeAmountInPlusFee += amountInPlusFee;
        swapState.rangeAmountOut += amountOut;
      }

      // if we reached the next tick, i.e. finished the current range
      if (sqrtPriceTargetX96 == sqrtPriceNextX96) {
        if (initialized) {
          // store the tick liquidity and positive EG amount of the current range
          TICK_LIQUIDITY_PAIRS_SLOT.offset(swapState.numInitializedTicks).tstore(
            MathExt.packTickLiquidity(tickNext, swapState.liquidity)
          );

          // calculate the EG amount generated by the current range
          uint256 rangeEGAmount = MathExt.calculateEGAmount(
            swapState.rangeAmountInPlusFee, swapState.rangeAmountOut, inverseFairExchangeRate
          );
          // store the EG amount of the current range
          RANGE_EG_AMOUNTS_SLOT.offset(swapState.numInitializedTicks).tstore(rangeEGAmount);
          // update the sum of the EG amounts over all ranges
          swapState.sumRangeEGAmounts += rangeEGAmount;

          // increment the number of initialized ticks
          swapState.numInitializedTicks++;

          // reset the range amounts for the next range
          swapState.rangeAmountInPlusFee = 0;
          swapState.rangeAmountOut = 0;

          // update the liquidity
          (, int128 liquidityNet) = getTickLiquidity(poolId, tickNext);
          swapState.liquidity =
            LiquidityMath.addDelta(swapState.liquidity, zeroForOne ? -liquidityNet : liquidityNet);
        }
        swapState.tick = zeroForOne ? tickNext - 1 : tickNext;
        swapState.sqrtPriceX96 = sqrtPriceNextX96;
      }

      // if we reached the end price, break
      if (sqrtPriceTargetX96 == sqrtPriceAfterX96) {
        break;
      }
    }

    // update the sum with the EG amount of the last range
    lastRangeEGAmount = MathExt.calculateEGAmount(
      swapState.rangeAmountInPlusFee, swapState.rangeAmountOut, inverseFairExchangeRate
    );
    swapState.sumRangeEGAmounts += lastRangeEGAmount;
  }

  /// @notice Updates the ticks with the EG amounts
  function updateTicks(
    State storage self,
    bool zeroForOne,
    uint256 lpEGAmount,
    SwapState memory swapState,
    uint256 lastRangeEGAmount
  ) internal {
    uint256 egGrowthGlobal0X128 = self.egGrowthGlobal0X128;
    uint256 egGrowthGlobal1X128 = self.egGrowthGlobal1X128;

    uint256 numInitializedTicks = swapState.numInitializedTicks;
    uint256 sumRangeEGAmounts = swapState.sumRangeEGAmounts;

    for (uint256 index = 0; index < numInitializedTicks; index++) {
      (int24 tickNext, uint128 liquidity) =
        MathExt.unpackTickLiquidity(TICK_LIQUIDITY_PAIRS_SLOT.offset(index).tloadUint256());
      uint256 rangeEGAmount = RANGE_EG_AMOUNTS_SLOT.offset(index).tloadUint256();

      // scale the EG amount since we do not penalize the ranges that generate negative EG
      /// @dev can't overflow
      uint256 scaledEGAmount = lpEGAmount.simpleMulDiv(rangeEGAmount, sumRangeEGAmounts);

      // add the EG amount to the global EG growth of the output token
      /// @dev can't overflow
      uint256 egPerLiquidity = scaledEGAmount.simpleMulDiv(FixedPoint128.Q128, liquidity);
      if (zeroForOne) {
        egGrowthGlobal1X128 += egPerLiquidity;
      } else {
        egGrowthGlobal0X128 += egPerLiquidity;
      }

      // run the tick transition
      self.ticks.cross(tickNext, egGrowthGlobal0X128, egGrowthGlobal1X128);
    }

    // add the EG amount of the last range to the global EG growth
    {
      uint256 scaledEGAmount = lpEGAmount.simpleMulDiv(lastRangeEGAmount, sumRangeEGAmounts);
      uint256 egPerLiquidity = scaledEGAmount.simpleMulDiv(FixedPoint128.Q128, swapState.liquidity);

      if (zeroForOne) {
        egGrowthGlobal1X128 += egPerLiquidity;
      } else {
        egGrowthGlobal0X128 += egPerLiquidity;
      }
    }

    // update the global EG growth in storage
    if (zeroForOne) {
      self.egGrowthGlobal1X128 = egGrowthGlobal1X128;
    } else {
      self.egGrowthGlobal0X128 = egGrowthGlobal0X128;
    }
  }
}
