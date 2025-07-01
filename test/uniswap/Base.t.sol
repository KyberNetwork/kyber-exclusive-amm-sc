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
      'UniswapV4FFHook.sol',
      abi.encode(
        admin,
        quoteSigner,
        egRecipient,
        newAddressArray(operator),
        newAddressArray(guardian),
        manager
      ),
      address(hook)
    );
  }

  function initPools(PoolConfig memory poolConfig) internal {
    boundPoolConfig(poolConfig);
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
  }

  function addLiquidity(AddLiquidityConfig memory addLiquidityConfig) internal {
    ModifyLiquidityParams memory params = ModifyLiquidityParams({
      tickLower: addLiquidityConfig.lowerTick,
      tickUpper: addLiquidityConfig.upperTick,
      liquidityDelta: addLiquidityConfig.liquidityDelta,
      salt: 0
    });
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    params = createFuzzyLiquidityParamsWithTightBound(
      keyWithoutHook, params, sqrtPriceX96, NUM_POSITIONS_AND_SWAPS
    );

    try modifyLiquidityNoChecks.modifyLiquidity(keyWithoutHook, params, '') {
      modifyLiquidityNoChecks.modifyLiquidity(keyWithHook, params, '');
    } catch (bytes memory reason) {
      assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
    }
  }

  function swapWithBothPools(SwapConfig memory swapConfig, bool toExpectEmit, bool toExpectRevert)
    internal
    returns (uint256 totalEGAmount)
  {
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

    bytes memory signature = sign(quoteSignerKey, getDigest(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    if (toExpectEmit) {
      vm.expectEmit(true, true, true, true, address(hook));
      emit IFFHookNonces.UseNonce(swapConfig.nonce);
    }
    if (toExpectRevert) {
      vm.expectRevert(
        abi.encodeWithSelector(
          CustomRevert.WrappedError.selector,
          hook,
          IHooks.beforeSwap.selector,
          abi.encodeWithSelector(IFFHookNonces.NonceAlreadyUsed.selector, swapConfig.nonce),
          abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        )
      );
    }

    uint256 gasWithHook;
    {
      uint256 gasLeft = gasleft();
      swapRouter.swap(keyWithHook, params, testSettings, hookData);
      gasWithHook = gasLeft - gasleft();
    }

    // vm.writeLine(
    //   'snapshots/uniswap/swapWithBothPools.csv',
    //   string.concat(vm.toString(gasWithoutHook), ',', vm.toString(gasWithHook))
    // );
  }

  function swapWithHookOnly(SwapConfig memory swapConfig) internal {
    SwapParams memory params = SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    bytes memory signature = sign(quoteSignerKey, getDigest(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  function getDigest(SwapConfig memory swapConfig) internal view returns (bytes32) {
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
