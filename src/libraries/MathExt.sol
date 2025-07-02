// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPoint128} from 'uniswap/v4-core/src/libraries/FixedPoint128.sol';
import {ProtocolFeeLibrary} from 'uniswap/v4-core/src/libraries/ProtocolFeeLibrary.sol';
import {SqrtPriceMath} from 'uniswap/v4-core/src/libraries/SqrtPriceMath.sol';
import {UnsafeMath} from 'uniswap/v4-core/src/libraries/UnsafeMath.sol';

library MathExt {
  using UnsafeMath for uint256;
  using ProtocolFeeLibrary for uint24;
  using ProtocolFeeLibrary for uint16;

  /// @notice The denominator for the protocol fee
  uint24 constant PIPS_DENOMINATOR = 1_000_000;

  /// @notice Calculates the amount of EG generated given delta
  function calculateEGAmount(int256 delta, bool zeroForOne, uint256 inverseFairExchangeRate)
    internal
    pure
    returns (uint256)
  {
    uint256 amountIn;
    uint256 amountOut;
    if (zeroForOne) {
      (amountIn, amountOut) = unpackDelta(delta);
    } else {
      (amountOut, amountIn) = unpackDelta(delta);
    }
    amountIn = negate(amountIn);

    return calculateEGAmount(amountIn, amountOut, inverseFairExchangeRate);
  }

  /// @notice Calculates the amount of EG generated given input and output amount
  function calculateEGAmount(uint256 amountIn, uint256 amountOut, uint256 inverseFairExchangeRate)
    internal
    pure
    returns (uint256 egAmount)
  {
    /// @dev can't overflow
    uint256 fairAmountOut = amountIn.simpleMulDiv(FixedPoint128.Q128, inverseFairExchangeRate);
    unchecked {
      return amountOut > fairAmountOut ? amountOut - fairAmountOut : 0;
    }
  }

  /// @notice Calculates the swap fee from the protocol fee and the LP fee
  function calculateSwapFee(uint24 protocolFee, uint24 lpFee, bool zeroForOne)
    internal
    pure
    returns (uint24 swapFee)
  {
    uint16 _protocolFee =
      zeroForOne ? protocolFee.getZeroForOneFee() : protocolFee.getOneForZeroFee();

    return _protocolFee == 0 ? lpFee : _protocolFee.calculateSwapFee(lpFee);
  }

  /// @notice Calculates the input and output amounts for a price movement
  function calculateSwapAmounts(
    uint160 sqrtPriceCurrentX96,
    uint160 sqrtPriceNextX96,
    uint128 liquidity,
    bool zeroForOne,
    uint24 feePips
  ) internal pure returns (uint256 amountInPlusFee, uint256 amountOut) {
    uint256 amountIn = zeroForOne
      ? SqrtPriceMath.getAmount0Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, true)
      : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);

    /// @dev can't overflow
    amountInPlusFee = amountIn.simpleMulDiv(PIPS_DENOMINATOR, PIPS_DENOMINATOR - feePips);

    amountOut = zeroForOne
      ? SqrtPriceMath.getAmount1Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, false)
      : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, false);
  }

  /// @notice Packs a tick and liquidity into a single uint256
  function packTickLiquidity(int24 tick, uint128 liquidity) internal pure returns (uint256 packed) {
    assembly ("memory-safe") {
      packed := or(shl(128, tick), liquidity)
    }
  }

  /// @notice Unpacks a tick and liquidity from a single uint256
  function unpackTickLiquidity(uint256 packed)
    internal
    pure
    returns (int24 tick, uint128 liquidity)
  {
    assembly ("memory-safe") {
      tick := shr(128, packed)
      liquidity := and(packed, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    }
  }

  /// @notice Unpacks a delta into two amounts
  function unpackDelta(int256 delta) internal pure returns (uint256 amount0, uint256 amount1) {
    assembly {
      amount0 := sar(128, delta)
      amount1 := signextend(15, delta)
    }
  }

  /// @notice Negates a uint256
  function negate(uint256 value) internal pure returns (uint256 negated) {
    assembly {
      negated := sub(0, value)
    }
  }
}
