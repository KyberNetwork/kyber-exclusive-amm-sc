// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';

import 'src/interfaces/IKEMHook.sol';
import 'src/interfaces/IUnorderedNonce.sol';

abstract contract BaseTest is Test {
  /// @dev The minimum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MIN_TICK)
  uint160 constant MIN_SQRT_PRICE = 4_295_128_739;

  /// @dev The maximum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MAX_TICK)
  uint160 constant MAX_SQRT_PRICE =
    1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

  /// @dev The number of tests in a multiple test config
  uint256 constant MULTIPLE_TEST_CONFIG_LENGTH = 20;

  struct PoolConfig {
    uint24 fee;
    int24 tickSpacing;
    int256 sqrtPriceX96seed;
    uint160 sqrtPriceX96;
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
    int256 maxExchangeRate;
    int256 exchangeRateDenom;
    uint256 nonce;
    uint256 expiryTime;
    bool needExceed;
  }

  struct AddLiquidityAndSwapConfig {
    AddLiquidityConfig addLiquidityConfig;
    SwapConfig swapConfig;
  }

  struct SingleTestConfig {
    PoolConfig poolConfig;
    AddLiquidityConfig addLiquidityConfig;
    SwapConfig swapConfig;
  }

  struct MultipleTestConfig {
    PoolConfig poolConfig;
    AddLiquidityAndSwapConfig[MULTIPLE_TEST_CONFIG_LENGTH] addLiquidityAndSwapConfigs;
    uint256 needClaimFlags;
  }

  address owner;
  address operator;
  address quoteSigner;
  uint256 quoteSignerKey;
  address egRecipient;

  address[] actors;

  IKEMHook hook;

  function setUp() public virtual {
    owner = makeAddr('owner');
    operator = makeAddr('operator');
    (quoteSigner, quoteSignerKey) = makeAddrAndKey('quoteSigner');
    egRecipient = makeAddr('egRecipient');
    actors = [owner, operator, quoteSigner, egRecipient, makeAddr('anyone')];

    vm.deal(address(this), type(uint256).max);
  }

  function boundFee(uint24 fee) internal pure returns (uint24) {
    return uint24(bound(fee, 0, 999_999));
  }

  function boundTickSpacing(int24 tickSpacing) internal pure returns (int24) {
    return int24(bound(tickSpacing, 1, 16_383));
  }

  function boundSwapConfig(SwapConfig memory swapConfig, uint160 sqrtPriceX96)
    internal
    view
    returns (SwapConfig memory)
  {
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
    swapConfig.maxExchangeRate =
      bound(swapConfig.maxExchangeRate, 0, type(int256).max / -swapConfig.amountSpecified);
    swapConfig.expiryTime = bound(swapConfig.expiryTime, block.timestamp, type(uint128).max);

    return swapConfig;
  }

  function boundExchangeRateDenom(
    SwapConfig memory swapConfig,
    int128 amountIn,
    int128 amountOutWithoutHook
  ) internal pure {
    int256 border = amountOutWithoutHook > 0
      ? amountIn * swapConfig.maxExchangeRate / amountOutWithoutHook
      : type(int256).max;
    swapConfig.exchangeRateDenom = swapConfig.needExceed && border != type(int256).max
      || border == 0
      ? bound(swapConfig.exchangeRateDenom, border + 1, type(int256).max)
      : bound(swapConfig.exchangeRateDenom, 1, border);
  }

  function getSignature(uint256 privKey, bytes32 digest)
    internal
    pure
    returns (bytes memory signature)
  {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
    signature = abi.encodePacked(r, s, v);
  }

  function newAddressesLength1(address addr) internal pure returns (address[] memory addresses) {
    addresses = new address[](1);
    addresses[0] = addr;
  }

  function newUint256sLength1(uint256 value) internal pure returns (uint256[] memory values) {
    values = new uint256[](1);
    values[0] = value;
  }
}
