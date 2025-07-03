// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';

import 'src/interfaces/IFFHook.sol';

import {Pausable} from 'openzeppelin-contracts/contracts/utils/Pausable.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {FixedPoint128, MathExt} from 'src/libraries/MathExt.sol';
import {TickMath as UniswapTickMath} from 'uniswap/v4-core/src/libraries/TickMath.sol';

import 'ks-common-sc/src/base/Management.sol';
import 'ks-common-sc/src/interfaces/ICommon.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';

interface IFFHookHarness is IFFHook {
  function updateProtocolEGUnclaimed(address token, uint256 amount) external;
}

abstract contract BaseHookTest is Test {
  using MathExt for *;

  /// @dev The number of liquidity positions
  uint256 constant NUM_POSITIONS_AND_SWAPS = 20;

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

  uint256[] totalEGAmounts = new uint256[](2);
  uint256[] protocolEGAmounts = new uint256[](2);

  uint256[] alivePositions;

  int24 minUsableTick;
  int24 maxUsableTick;
  uint160 minUsableSqrtPriceX96;
  uint160 maxUsableSqrtPriceX96;

  IFFHook hook;

  function setUp() public virtual {
    admin = makeAddr('admin');
    (quoteSigner, quoteSignerKey) = makeAddrAndKey('quoteSigner');
    egRecipient = makeAddr('egRecipient');
    operator = makeAddr('operator');
    guardian = makeAddr('guardian');
    rescuer = makeAddr('rescuer');

    actors = [admin, operator, quoteSigner, egRecipient, guardian, rescuer, makeAddr('anyone')];

    deal(address(this), 2 ** 255);
  }

  function createFuzzyPoolConfig(PoolConfig memory poolConfig)
    internal
    pure
    returns (PoolConfig memory)
  {
    poolConfig.lpFee = uint24(bound(poolConfig.lpFee, 0, 1000));
    poolConfig.tickSpacing = int24(bound(poolConfig.tickSpacing, 1, 1023));
    poolConfig.protocolEGFee = uint24(bound(poolConfig.protocolEGFee, 0, 1000));

    return poolConfig;
  }

  function createFuzzySwapConfig(bytes32 poolId, SwapConfig memory swapConfig)
    internal
    view
    returns (SwapConfig memory)
  {
    (swapConfig.sqrtPriceLimitX96, swapConfig.zeroForOne) =
      boundSqrtPriceLimitX96(poolId, swapConfig.sqrtPriceLimitX96);
    swapConfig.amountSpecified = bound(swapConfig.amountSpecified, type(int128).min + 1, -1);
    swapConfig.maxAmountIn =
      bound(swapConfig.maxAmountIn, -swapConfig.amountSpecified, type(int256).max - 1);
    swapConfig.nonce = bound(swapConfig.nonce, 1, type(uint256).max);
    swapConfig.expiryTime = bound(swapConfig.expiryTime, block.timestamp, type(uint128).max);

    return swapConfig;
  }

  function boundSqrtPriceLimitX96(bytes32 poolId, uint160 sqrtPriceLimitX96)
    internal
    view
    returns (uint160, bool)
  {
    (uint160 sqrtPriceX96,,,) = getSlot0(poolId);
    sqrtPriceLimitX96 =
      uint160(bound(sqrtPriceLimitX96, minUsableSqrtPriceX96, maxUsableSqrtPriceX96));
    if (sqrtPriceLimitX96 == sqrtPriceX96) {
      sqrtPriceLimitX96 =
        sqrtPriceLimitX96 > minUsableSqrtPriceX96 ? sqrtPriceLimitX96 - 1 : sqrtPriceLimitX96 + 1;
    }

    return (sqrtPriceLimitX96, sqrtPriceLimitX96 < sqrtPriceX96);
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
    // limit the inverse fair exchange rate to be within 5% of the actual inverse exchange rate
    uint256 minInverseFairExchangeRate = inverseExchangeRate - inverseExchangeRate / 20;
    uint256 maxInverseFairExchangeRate = inverseExchangeRate
      + Math.min(type(uint256).max - inverseExchangeRate, inverseExchangeRate / 20);

    return bound(inverseFairExchangeRate, minInverseFairExchangeRate, maxInverseFairExchangeRate);
  }

  function createFuzzyActionsOrdering(uint256[NUM_POSITIONS_AND_SWAPS * 3] memory actions)
    internal
    returns (uint256[NUM_POSITIONS_AND_SWAPS * 3] memory)
  {
    uint256 currentSwapIndex = 0;
    uint256 currentPositionIndex = 0;

    for (uint256 i = 0; i < actions.length; i++) {
      uint256 actionType;
      if (alivePositions.length == 0) {
        if (currentSwapIndex == NUM_POSITIONS_AND_SWAPS) {
          actionType = 1;
        } else if (currentPositionIndex == NUM_POSITIONS_AND_SWAPS) {
          actionType = 0;
        } else {
          actionType = bound(actions[i], 0, 1);
        }
      } else {
        actionType = bound(actions[i], 0, 2);
      }

      if (actionType == 0) {
        actions[i] = currentSwapIndex++;
      } else if (actionType == 1) {
        actions[i] = currentPositionIndex++;
      } else {
        actions[i] = pop(alivePositions, actions[i]);
      }

      actions[i] += actionType * NUM_POSITIONS_AND_SWAPS;
    }

    return actions;
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

  function push(uint256[] storage arr, uint256 value) internal {
    arr.push(value);
  }

  function pop(uint256[] storage arr, uint256 index) internal returns (uint256 value) {
    index = bound(index, 0, arr.length - 1);
    value = arr[index];
    arr[index] = arr[arr.length - 1];
    arr.pop();
  }

  function minInt24(int24 a, int24 b) internal pure returns (int24) {
    return a < b ? a : b;
  }

  function maxInt24(int24 a, int24 b) internal pure returns (int24) {
    return a > b ? a : b;
  }
}
