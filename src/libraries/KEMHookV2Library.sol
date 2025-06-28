// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ProtocolFeeLibrary} from 'uniswap/v4-core/src/libraries/ProtocolFeeLibrary.sol';
import {SqrtPriceMath} from 'uniswap/v4-core/src/libraries/SqrtPriceMath.sol';

struct PoolState {
  uint160 sqrtPriceX96;
  int24 tick;
  uint24 swapFee;
  uint128 liquidity;
}

library KEMHookV2Library {
  using ProtocolFeeLibrary for *;

  function toPoolState(bytes32 data, bool zeroForOne)
    internal
    pure
    returns (PoolState memory poolState)
  {
    uint160 _sqrtPriceX96;
    int24 _tick;
    uint24 protocolFee;
    uint24 lpFee;
    assembly ("memory-safe") {
      // bottom 160 bits of data
      _sqrtPriceX96 := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
      // next 24 bits of data
      _tick := signextend(2, shr(160, data))
      // next 24 bits of data
      protocolFee := and(shr(184, data), 0xFFFFFF)
      // last 24 bits of data
      lpFee := and(shr(208, data), 0xFFFFFF)
    }

    poolState.sqrtPriceX96 = _sqrtPriceX96;
    poolState.tick = _tick;
    poolState.swapFee = (
      zeroForOne ? protocolFee.getZeroForOneFee() : protocolFee.getOneForZeroFee()
    ).calculateSwapFee(lpFee);
  }

  function sqrtPriceX96(bytes32 data) internal pure returns (uint160 _sqrtPriceX96) {
    assembly ("memory-safe") {
      _sqrtPriceX96 := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    }
  }

  function tick(bytes32 data) internal pure returns (int24 _tick) {
    assembly ("memory-safe") {
      _tick := signextend(2, shr(160, data))
    }
  }

  function unpackDelta(int256 delta) internal pure returns (uint256 amount0, uint256 amount1) {
    assembly {
      amount0 := sar(128, delta)
      amount1 := signextend(15, delta)
    }
  }

  function negate(uint256 value) internal pure returns (uint256 negated) {
    assembly {
      negated := sub(value, mul(value, 2))
    }
  }

  function toTickLiquidity(int24 _tick, uint128 liquidity)
    internal
    pure
    returns (uint256 tickLiquidity)
  {
    assembly {
      tickLiquidity := or(shl(128, _tick), liquidity)
    }
  }

  function unpackTickLiquidity(uint256 tickLiquidity)
    internal
    pure
    returns (int24 _tick, uint128 liquidity)
  {
    assembly {
      _tick := shr(128, tickLiquidity)
      liquidity := and(tickLiquidity, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    }
  }

  function calculateSwapAmounts(
    uint160 sqrtPriceCurrentX96,
    uint160 sqrtPriceNextX96,
    uint128 liquidity,
    bool zeroForOne
  ) internal pure returns (uint256 amountIn, uint256 amountOut) {
    amountIn = zeroForOne
      ? SqrtPriceMath.getAmount0Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, true)
      : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);
    amountOut = zeroForOne
      ? SqrtPriceMath.getAmount1Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, false)
      : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, false);
  }
}
