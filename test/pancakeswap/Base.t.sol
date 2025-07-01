// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.t.sol';

import 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLHooks.sol';
import 'pancakeswap/infinity-core/src/types/PoolKey.sol';

import 'pancakeswap/infinity-core/src/libraries/CustomRevert.sol';
import 'pancakeswap/infinity-core/src/pool-cl/libraries/CLPoolParametersHelper.sol';

import 'pancakeswap/infinity-core/test/helpers/TokenFixture.sol';
import 'pancakeswap/infinity-core/test/pool-cl/helpers/Deployers.sol';
import 'pancakeswap/infinity-core/test/pool-cl/helpers/Fuzzers.sol';

contract PancakeSwapHookBaseTest is BaseHookTest, Deployers, TokenFixture, Fuzzers {
  using CLPoolParametersHelper for bytes32;

  IVault public vault;
  CLPoolManager public manager;
  CLPoolManagerRouter public swapRouter;

  PoolKey keyWithoutHook;
  PoolId idWithoutHook;
  PoolKey keyWithHook;
  PoolId idWithHook;

  CLPoolManagerRouter.SwapTestSettings testSettings =
    CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

  address[] tokens;

  function setUp() public override {
    super.setUp();

    (vault, manager) = createFreshManager();
    swapRouter = new CLPoolManagerRouter(vault, manager);
    deployMintAndApprove2Currencies();
    deployFreshHook();

    tokens = new address[](2);
    tokens[0] = Currency.unwrap(currency0);
    tokens[1] = Currency.unwrap(currency1);

    vm.label(address(hook), 'FFHook');
    vm.label(tokens[0], 'Token0');
    vm.label(tokens[1], 'Token1');
  }

  function deployMintAndApprove2Currencies() internal {
    MockERC20 token0 = deployMintAndApproveToken();
    MockERC20 token1 = deployMintAndApproveToken();

    (currency0, currency1) = SortTokens.sort(token0, token1);
  }

  function deployMintAndApproveToken() internal returns (MockERC20) {
    MockERC20 token = deployTokens(1, 2 ** 255)[0];

    token.approve(address(swapRouter), Constants.MAX_UINT256);

    return token;
  }

  function deployFreshHook() internal {
    hook = IFFHook(
      address(
        uint160(
          HOOKS_BEFORE_INITIALIZE_OFFSET | HOOKS_AFTER_ADD_LIQUIDITY_OFFSET
            | HOOKS_AFTER_REMOVE_LIQUIDITY_OFFSET | HOOKS_BEFORE_SWAP_OFFSET | HOOKS_AFTER_SWAP_OFFSET
            | HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET | HOOKS_AFTER_ADD_LIQUIDIY_RETURNS_DELTA_OFFSET
            | HOOKS_AFTER_REMOVE_LIQUIDIY_RETURNS_DELTA_OFFSET
        )
      )
    );
    deployCodeTo(
      'PancakeSwapInfinityFFHook.sol',
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

    keyWithoutHook = PoolKey(
      currency0,
      currency1,
      IHooks(address(0)),
      manager,
      poolConfig.lpFee,
      bytes32(0).setTickSpacing(poolConfig.tickSpacing)
    );
    idWithoutHook = keyWithoutHook.toId();

    keyWithHook = PoolKey(
      currency0,
      currency1,
      IHooks(address(hook)),
      manager,
      poolConfig.lpFee,
      bytes32(uint256(IHooks(address(hook)).getHooksRegistrationBitmap())).setTickSpacing(
        poolConfig.tickSpacing
      )
    );
    idWithHook = keyWithHook.toId();

    manager.initialize(keyWithoutHook, poolConfig.sqrtPriceX96);
    manager.initialize(keyWithHook, poolConfig.sqrtPriceX96);

    vm.prank(admin);
    hook.updateProtocolEGFee(PoolId.unwrap(idWithHook), poolConfig.protocolEGFee);
  }

  function addLiquidity(AddLiquidityConfig memory addLiquidityConfig) internal {
    ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams({
      tickLower: addLiquidityConfig.lowerTick,
      tickUpper: addLiquidityConfig.upperTick,
      liquidityDelta: addLiquidityConfig.liquidityDelta,
      salt: 0
    });
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    params = createFuzzyLiquidityParamsWithTightBound(
      keyWithoutHook, params, sqrtPriceX96, NUM_POSITIONS_AND_SWAPS
    );

    try swapRouter.modifyPosition(keyWithoutHook, params, '') {
      swapRouter.modifyPosition(keyWithHook, params, '');
    } catch (bytes memory reason) {
      assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
    }
  }

  function swapWithBothPools(SwapConfig memory swapConfig, bool toExpectEmit, bool toExpectRevert)
    internal
    returns (uint256 totalEGAmount)
  {
    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
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
          ICLHooks.beforeSwap.selector,
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
    //   'snapshots/pancakeswap/swapWithBothPools.csv',
    //   string.concat(vm.toString(gasWithoutHook), ',', vm.toString(gasWithHook))
    // );
  }

  function swapWithHookOnly(SwapConfig memory swapConfig) internal {
    ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
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
