// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';

import 'src/interfaces/IFFHook.sol';

import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {FixedPoint128, MathExt} from 'src/libraries/MathExt.sol';

import 'ks-common-sc/src/base/Management.sol';
import 'ks-common-sc/src/interfaces/ICommon.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';

interface IFFHookHarness is IFFHook {
  function updateProtocolEGUnclaimed(address token, uint256 amount) external;
}

abstract contract BaseHookTest is Test {
  using MathExt for *;

  /// @dev The minimum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MIN_TICK)
  uint160 constant MIN_SQRT_PRICE = 4_295_128_739;

  /// @dev The maximum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MAX_TICK)
  uint160 constant MAX_SQRT_PRICE =
    1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

  /// @dev The number of liquidity positions
  uint256 constant NUM_POSITIONS_AND_SWAPS = 100;

  struct PoolConfig {
    uint24 lpFee;
    int24 tickSpacing;
    uint160 sqrtPriceX96;
    uint24 protocolEGFee;
  }

  struct AddLiquidityConfig {
    int24 lowerTick;
    int24 upperTick;
    int256 liquidityDelta;
  }

  struct SwapConfig {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
    int256 maxAmountIn;
    uint256 inverseFairExchangeRate;
    uint256 nonce;
    uint256 expiryTime;
  }

  address admin;
  address quoteSigner;
  uint256 quoteSignerKey;
  address egRecipient;
  address operator;
  address guardian;
  address rescuer;

  address[] actors;

  IFFHook hook;

  function setUp() public virtual {
    admin = makeAddr('admin');
    (quoteSigner, quoteSignerKey) = makeAddrAndKey('quoteSigner');
    egRecipient = makeAddr('egRecipient');
    operator = makeAddr('operator');
    guardian = makeAddr('guardian');
    rescuer = makeAddr('rescuer');

    actors = [admin, operator, quoteSigner, egRecipient, guardian, rescuer, makeAddr('anyone')];
  }

  function boundPoolConfig(PoolConfig memory poolConfig) internal pure returns (PoolConfig memory) {
    poolConfig.lpFee = uint24(bound(poolConfig.lpFee, 0, 999_999));
    poolConfig.tickSpacing = int24(bound(poolConfig.tickSpacing, 1, 1023));
    poolConfig.protocolEGFee = uint24(bound(poolConfig.protocolEGFee, 0, 999_999));

    return poolConfig;
  }

  function boundSwapConfig(bytes32 poolId, SwapConfig memory swapConfig)
    internal
    view
    returns (SwapConfig memory)
  {
    (uint160 sqrtPriceX96,,,) = getSlot0(poolId);
    swapConfig.amountSpecified = bound(swapConfig.amountSpecified, type(int128).min + 1, -1);
    if (sqrtPriceX96 == MIN_SQRT_PRICE + 1) {
      swapConfig.sqrtPriceLimitX96 =
        uint160(bound(swapConfig.sqrtPriceLimitX96, MIN_SQRT_PRICE + 2, MAX_SQRT_PRICE - 1));
      swapConfig.zeroForOne = false;
    } else if (sqrtPriceX96 == MAX_SQRT_PRICE - 1) {
      swapConfig.sqrtPriceLimitX96 =
        uint160(bound(swapConfig.sqrtPriceLimitX96, MIN_SQRT_PRICE + 1, MAX_SQRT_PRICE - 2));
      swapConfig.zeroForOne = true;
    } else {
      swapConfig.sqrtPriceLimitX96 = uint160(
        swapConfig.zeroForOne
          ? bound(swapConfig.sqrtPriceLimitX96, MIN_SQRT_PRICE + 1, sqrtPriceX96 - 1)
          : bound(swapConfig.sqrtPriceLimitX96, sqrtPriceX96 + 1, MAX_SQRT_PRICE - 1)
      );
    }
    swapConfig.maxAmountIn =
      bound(swapConfig.maxAmountIn, -swapConfig.amountSpecified, type(int256).max - 1);
    swapConfig.nonce = bound(swapConfig.nonce, 1, type(uint256).max);
    swapConfig.expiryTime = bound(swapConfig.expiryTime, block.timestamp, type(uint128).max);

    return swapConfig;
  }

  function boundInverseFairExchangeRate(
    uint256 inverseFairExchangeRate,
    int256 delta,
    bool zeroForOne
  ) internal pure returns (uint256) {
    uint256 amountIn;
    uint256 amountOut;
    if (zeroForOne) {
      (amountIn, amountOut) = delta.unpackDelta();
    } else {
      (amountOut, amountIn) = delta.unpackDelta();
    }
    amountIn = amountIn.negate();

    if (amountOut == 0) {
      return 0;
    }

    uint256 inverseExchangeRate = amountIn * FixedPoint128.Q128 / amountOut;
    // bound the inverse fair exchange rate to be within 5% of the inverse exchange rate
    uint256 minInverseFairExchangeRate = inverseExchangeRate - inverseExchangeRate / 20;
    uint256 maxInverseFairExchangeRate = inverseExchangeRate
      + Math.min(type(uint256).max - inverseExchangeRate, inverseExchangeRate / 20);

    return bound(inverseFairExchangeRate, minInverseFairExchangeRate, maxInverseFairExchangeRate);
  }

  function getSlot0(bytes32 poolId)
    internal
    view
    virtual
    returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

  function sign(uint256 privKey, bytes32 digest) internal pure returns (bytes memory signature) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
    signature = abi.encodePacked(r, s, v);
  }

  function getHookData(SwapConfig memory swapConfig, bytes memory signature)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encode(
      swapConfig.maxAmountIn,
      swapConfig.inverseFairExchangeRate,
      swapConfig.nonce,
      swapConfig.expiryTime,
      signature
    );
  }

  function newAddressArray(address addr) internal pure returns (address[] memory addresses) {
    addresses = new address[](1);
    addresses[0] = addr;
  }

  function newUint256Array(uint256 value) internal pure returns (uint256[] memory values) {
    values = new uint256[](1);
    values[0] = value;
  }
}
