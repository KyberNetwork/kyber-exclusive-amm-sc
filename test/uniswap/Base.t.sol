// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.t.sol';

import 'uniswap/v4-core/src/types/PoolKey.sol';

import 'uniswap/v4-core/src/libraries/CustomRevert.sol';
import 'uniswap/v4-core/src/libraries/FixedPoint128.sol';

import 'uniswap/v4-core/src/test/Fuzzers.sol';
import 'uniswap/v4-core/test/utils/Deployers.sol';

contract UniswapHookBaseTest is BaseHookTest, Deployers, Fuzzers {
  using StateLibrary for IPoolManager;
  using SafeCast for uint256;

  PoolKey keyWithoutHook;
  PoolId idWithoutHook;
  PoolKey keyWithHook;
  PoolId idWithHook;

  PoolSwapTest.TestSettings testSettings =
    PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

  address[] tokens;

  function setUp() public override {
    super.setUp();

    deployFreshManagerAndRouters();
    deployMintAndApprove2Currencies();
    deployFreshHook();

    tokens = new address[](2);
    tokens[0] = Currency.unwrap(currency0);
    tokens[1] = Currency.unwrap(currency1);

    vm.label(address(hook), 'FFHook');
    vm.label(tokens[0], 'Token0');
    vm.label(tokens[1], 'Token1');
  }

  function deployFreshHook() internal {
    hook = IFFHook(
      address(
        uint160(
          Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
        )
      )
    );
    deployCodeTo(
      'UniswapV4FFHookHarness',
      abi.encode(
        admin,
        quoteSigner,
        egRecipient,
        newAddressArray(operator),
        newAddressArray(guardian),
        newAddressArray(rescuer),
        manager
      ),
      address(hook)
    );
  }

  function initPools(PoolConfig memory poolConfig) internal {
    createFuzzyPoolConfig(poolConfig);
    poolConfig.sqrtPriceX96 =
      createRandomSqrtPriceX96(poolConfig.tickSpacing, int256(uint256(poolConfig.sqrtPriceX96)));

    keyWithoutHook =
      PoolKey(currency0, currency1, poolConfig.lpFee, poolConfig.tickSpacing, IHooks(address(0)));
    idWithoutHook = keyWithoutHook.toId();

    keyWithHook =
      PoolKey(currency0, currency1, poolConfig.lpFee, poolConfig.tickSpacing, IHooks(address(hook)));
    idWithHook = keyWithHook.toId();

    manager.initialize(keyWithoutHook, poolConfig.sqrtPriceX96);
    manager.initialize(keyWithHook, poolConfig.sqrtPriceX96);

    vm.prank(admin);
    hook.updateProtocolEGFee(PoolId.unwrap(idWithHook), poolConfig.protocolEGFee);

    int24 tick = TickMath.getTickAtSqrtPrice(poolConfig.sqrtPriceX96);
    minUsableTick = maxInt24(tick - 75_000, TickMath.MIN_TICK);
    maxUsableTick = minInt24(tick + 75_000, TickMath.MAX_TICK);
    minUsableSqrtPriceX96 = TickMath.getSqrtPriceAtTick(minUsableTick) + 1;
    maxUsableSqrtPriceX96 = TickMath.getSqrtPriceAtTick(maxUsableTick) - 1;
  }

  function addLiquidityBothPools(AddLiquidityConfig memory addLiquidityConfig)
    internal
    returns (ModifyLiquidityParams memory params)
  {
    params = ModifyLiquidityParams({
      tickLower: addLiquidityConfig.lowerTick,
      tickUpper: addLiquidityConfig.upperTick,
      liquidityDelta: addLiquidityConfig.liquidityDelta,
      salt: 0
    });
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    _createFuzzyLiquidityParamsWithTightBound(
      keyWithoutHook, params, sqrtPriceX96, NUM_POSITIONS_AND_SWAPS
    );

    modifyLiquidityNoChecks.modifyLiquidity(keyWithoutHook, params, '');
    modifyLiquidityNoChecks.modifyLiquidity(keyWithHook, params, '');
  }

  function removeLiquidityBothPools(ModifyLiquidityParams memory params) internal {
    if (params.liquidityDelta > 0) {
      params.liquidityDelta = -params.liquidityDelta;
    }
    if (params.liquidityDelta != 0) {
      modifyLiquidityNoChecks.modifyLiquidity(keyWithoutHook, params, '');
      modifyLiquidityNoChecks.modifyLiquidity(keyWithHook, params, '');
    }
  }

  function swapBothPools(SwapConfig memory swapConfig) internal returns (uint256 totalEGAmount) {
    SwapParams memory params = SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    BalanceDelta deltaWithoutHook;
    uint256 gasWithoutHook;
    {
      uint256 gasLeft = gasleft();
      try swapRouter.swap(keyWithoutHook, params, testSettings, '') returns (BalanceDelta delta) {
        deltaWithoutHook = delta;
      } catch (bytes memory reason) {
        assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
        return 0;
      }
      gasWithoutHook = gasLeft - gasleft();
    }

    swapConfig.inverseFairExchangeRate = boundInverseFairExchangeRate(
      swapConfig.inverseFairExchangeRate,
      BalanceDelta.unwrap(deltaWithoutHook),
      swapConfig.zeroForOne
    );
    totalEGAmount = MathExt.calculateEGAmount(
      BalanceDelta.unwrap(deltaWithoutHook),
      swapConfig.zeroForOne,
      swapConfig.inverseFairExchangeRate
    );

    bytes memory signature = sign(quoteSignerKey, hash(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    if (swapConfig.nonce != 0) {
      vm.expectEmit(true, true, true, true, address(hook));
      emit IFFHookNonces.UseNonce(swapConfig.nonce);
    }

    uint256 gasWithHook;
    {
      uint256 gasLeft = gasleft();
      swapRouter.swap(keyWithHook, params, testSettings, hookData);
      gasWithHook = gasLeft - gasleft();
    }
  }

  function addLiquidityBothPools_pausedHook(AddLiquidityConfig memory addLiquidityConfig)
    internal
    returns (ModifyLiquidityParams memory params)
  {
    params = ModifyLiquidityParams({
      tickLower: addLiquidityConfig.lowerTick,
      tickUpper: addLiquidityConfig.upperTick,
      liquidityDelta: addLiquidityConfig.liquidityDelta,
      salt: 0
    });
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    _createFuzzyLiquidityParamsWithTightBound(
      keyWithoutHook, params, sqrtPriceX96, NUM_POSITIONS_AND_SWAPS
    );

    BalanceDelta deltaWithoutHook =
      modifyLiquidityNoChecks.modifyLiquidity(keyWithoutHook, params, '');
    BalanceDelta deltaWithHook = modifyLiquidityNoChecks.modifyLiquidity(keyWithHook, params, '');
    assertEq(
      BalanceDelta.unwrap(deltaWithHook),
      BalanceDelta.unwrap(deltaWithoutHook),
      'add liquidity with paused hook should be the same as add liquidity without hook'
    );
  }

  function removeLiquidityBothPools_pausedHook(ModifyLiquidityParams memory params) internal {
    if (params.liquidityDelta > 0) {
      params.liquidityDelta = -params.liquidityDelta;
    }
    if (params.liquidityDelta != 0) {
      BalanceDelta deltaWithoutHook =
        modifyLiquidityNoChecks.modifyLiquidity(keyWithoutHook, params, '');
      BalanceDelta deltaWithHook = modifyLiquidityNoChecks.modifyLiquidity(keyWithHook, params, '');
      assertEq(
        BalanceDelta.unwrap(deltaWithHook),
        BalanceDelta.unwrap(deltaWithoutHook),
        'remove liquidity with paused hook should be the same as remove liquidity without hook'
      );
    }
  }

  function swapBothPools_pausedHook(SwapConfig memory swapConfig) internal {
    SwapParams memory params = SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    BalanceDelta deltaWithoutHook;
    try swapRouter.swap(keyWithoutHook, params, testSettings, '') returns (BalanceDelta delta) {
      deltaWithoutHook = delta;
    } catch (bytes memory reason) {
      assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
      return;
    }

    BalanceDelta deltaWithHook = swapRouter.swap(keyWithHook, params, testSettings, '');
    assertEq(
      BalanceDelta.unwrap(deltaWithHook),
      BalanceDelta.unwrap(deltaWithoutHook),
      'swap with paused hook should be the same as swap without hook'
    );
  }

  function addLiquidityOnlyHook(AddLiquidityConfig memory addLiquidityConfig) internal {
    ModifyLiquidityParams memory params = ModifyLiquidityParams({
      tickLower: addLiquidityConfig.lowerTick,
      tickUpper: addLiquidityConfig.upperTick,
      liquidityDelta: addLiquidityConfig.liquidityDelta,
      salt: 0
    });
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    _createFuzzyLiquidityParamsWithTightBound(
      keyWithoutHook, params, sqrtPriceX96, NUM_POSITIONS_AND_SWAPS
    );

    modifyLiquidityNoChecks.modifyLiquidity(keyWithHook, params, '');
  }

  function swapOnlyHook(SwapConfig memory swapConfig) internal {
    SwapParams memory params = SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    bytes memory signature = sign(quoteSignerKey, hash(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  function _createFuzzyLiquidityParamsWithTightBound(
    PoolKey memory key,
    ModifyLiquidityParams memory params,
    uint160 sqrtPriceX96,
    uint256 maxPositions
  ) internal pure {
    (params.tickLower, params.tickUpper) = boundTicks(key, params.tickLower, params.tickUpper);
    int256 liquidityDeltaFromAmounts =
      _getLiquidityDeltaFromAmounts(params.tickLower, params.tickUpper, sqrtPriceX96);

    params.liquidityDelta = boundLiquidityDeltaTightly(
      key, params.liquidityDelta, liquidityDeltaFromAmounts, maxPositions
    );
  }

  function _getLiquidityDeltaFromAmounts(int24 tickLower, int24 tickUpper, uint160 sqrtPriceX96)
    internal
    pure
    returns (int256)
  {
    // First get the maximum amount0 and maximum amount1 that can be deposited at this range.
    (uint256 maxAmount0, uint256 maxAmount1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      TickMath.getSqrtPriceAtTick(tickLower),
      TickMath.getSqrtPriceAtTick(tickUpper),
      uint128(type(int128).max)
    );

    uint256 amount0 = type(uint96).max;
    uint256 amount1 = type(uint96).max;

    maxAmount0 = maxAmount0 > amount0 ? amount0 : maxAmount0;
    maxAmount1 = maxAmount1 > amount1 ? amount1 : maxAmount1;

    int256 liquidityMaxByAmount = uint256(
      LiquidityAmounts.getLiquidityForAmounts(
        sqrtPriceX96,
        TickMath.getSqrtPriceAtTick(tickLower),
        TickMath.getSqrtPriceAtTick(tickUpper),
        maxAmount0,
        maxAmount1
      )
    ).toInt256();

    return liquidityMaxByAmount;
  }

  function hash(SwapConfig memory swapConfig) internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        swapRouter,
        idWithHook,
        swapConfig.zeroForOne,
        swapConfig.maxAmountIn,
        swapConfig.inverseFairExchangeRate,
        swapConfig.nonce,
        swapConfig.expiryTime
      )
    );
  }

  function getSlot0(bytes32 poolId) internal view override returns (uint160, int24, uint24, uint24) {
    return manager.getSlot0(PoolId.wrap(poolId));
  }
}
