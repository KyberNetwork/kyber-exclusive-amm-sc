// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.t.sol';

import 'src/UniswapV4KEMHook.sol';
import 'src/base/BaseKEMHook.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import 'uniswap/v4-core/src/libraries/CustomRevert.sol';

import 'uniswap/v4-core/src/test/Fuzzers.sol';

import 'uniswap/v4-core/src/types/PoolKey.sol';
import 'uniswap/v4-core/test/utils/Deployers.sol';

contract UniswapHookBaseTest is BaseTest, Deployers, Fuzzers {
  using StateLibrary for IPoolManager;

  PoolKey keyWithoutHook;
  PoolId idWithoutHook;
  PoolKey keyWithHook;

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
  }

  function deployFreshHook() internal {
    hook = IKEMHook(
      address(
        uint160(
          Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        )
      )
    );
    deployCodeTo(
      'UniswapV4KEMHook.sol',
      abi.encode(manager, owner, newAddressesLength1(operator), quoteSigner, egRecipient),
      address(hook)
    );
  }

  function initPools(PoolConfig memory poolConfig) internal {
    poolConfig.fee = boundFee(poolConfig.fee);
    poolConfig.tickSpacing = boundTickSpacing(poolConfig.tickSpacing);
    poolConfig.sqrtPriceX96 =
      createRandomSqrtPriceX96(poolConfig.tickSpacing, poolConfig.sqrtPriceX96seed);

    keyWithoutHook =
      PoolKey(currency0, currency1, poolConfig.fee, poolConfig.tickSpacing, IHooks(address(0)));
    idWithoutHook = keyWithoutHook.toId();
    keyWithHook =
      PoolKey(currency0, currency1, poolConfig.fee, poolConfig.tickSpacing, IHooks(address(hook)));

    manager.initialize(keyWithoutHook, poolConfig.sqrtPriceX96);
    manager.initialize(keyWithHook, poolConfig.sqrtPriceX96);
  }

  function addLiquidity(AddLiquidityConfig memory addLiquidityConfig) internal {
    IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
      tickLower: addLiquidityConfig.lowerTick,
      tickUpper: addLiquidityConfig.upperTick,
      liquidityDelta: addLiquidityConfig.liquidityDelta,
      salt: 0
    });
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    params = createFuzzyLiquidityParamsWithTightBound(
      keyWithoutHook, params, sqrtPriceX96, MULTIPLE_TEST_CONFIG_LENGTH
    );

    try modifyLiquidityNoChecks.modifyLiquidity(keyWithoutHook, params, '') {
      modifyLiquidityNoChecks.modifyLiquidity(keyWithHook, params, '');
    } catch (bytes memory reason) {
      assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
    }
  }

  function boundSwapConfig(SwapConfig memory swapConfig) internal view returns (SwapConfig memory) {
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(idWithoutHook);
    return boundSwapConfig(swapConfig, sqrtPriceX96);
  }

  function swapWithBothPools(SwapConfig memory swapConfig, bool needClaim, bool needExpectRevert)
    internal
    returns (uint256 egAmount)
  {
    boundSwapConfig(swapConfig);

    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    BalanceDelta deltaWithoutHook;
    try swapRouter.swap(keyWithoutHook, params, testSettings, '') returns (BalanceDelta delta) {
      deltaWithoutHook = delta;
    } catch (bytes memory reason) {
      assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
      return 0;
    }

    int128 amountIn;
    int128 amountOutWithoutHook;
    if (swapConfig.zeroForOne) {
      amountIn = -deltaWithoutHook.amount0();
      amountOutWithoutHook = deltaWithoutHook.amount1();
    } else {
      amountIn = -deltaWithoutHook.amount1();
      amountOutWithoutHook = deltaWithoutHook.amount0();
    }

    boundExchangeRateDenom(swapConfig, amountIn, amountOutWithoutHook);

    bytes memory signature = getSignature(quoteSignerKey, getDigest(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    int256 maxAmountOut = amountIn * swapConfig.maxExchangeRate / swapConfig.exchangeRateDenom;
    egAmount =
      uint256(maxAmountOut < amountOutWithoutHook ? amountOutWithoutHook - maxAmountOut : int256(0));

    if (needExpectRevert) {
      vm.expectRevert(
        abi.encodeWithSelector(
          CustomRevert.WrappedError.selector,
          hook,
          IHooks.beforeSwap.selector,
          abi.encodeWithSelector(IUnorderedNonce.NonceAlreadyUsed.selector, swapConfig.nonce),
          abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        )
      );
    } else {
      vm.expectEmit(true, true, true, true, address(hook));
      emit IUnorderedNonce.UseNonce(swapConfig.nonce);
    }

    BalanceDelta deltaWithHook = swapRouter.swap(keyWithHook, params, testSettings, hookData);
    int128 amountOutWithHook;
    if (swapConfig.zeroForOne) {
      amountOutWithHook = deltaWithHook.amount1();
    } else {
      amountOutWithHook = deltaWithHook.amount0();
    }

    if (needClaim) {
      vm.prank(operator);
      try hook.claimEgTokens(tokens, new uint256[](2)) {}
      catch (bytes memory reason) {
        assertEq(reason, abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
      }
    }
  }

  function swapWithHookOnly(SwapConfig memory swapConfig) internal {
    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      zeroForOne: swapConfig.zeroForOne,
      amountSpecified: swapConfig.amountSpecified,
      sqrtPriceLimitX96: swapConfig.sqrtPriceLimitX96
    });

    bytes memory signature = getSignature(quoteSignerKey, getDigest(swapConfig));
    bytes memory hookData = getHookData(swapConfig, signature);

    swapRouter.swap(keyWithHook, params, testSettings, hookData);
  }

  function getDigest(SwapConfig memory swapConfig) internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        swapRouter,
        keyWithHook,
        swapConfig.zeroForOne,
        swapConfig.maxAmountIn,
        swapConfig.maxExchangeRate,
        swapConfig.exchangeRateDenom,
        swapConfig.nonce,
        swapConfig.expiryTime
      )
    );
  }

  function getHookData(SwapConfig memory swapConfig, bytes memory signature)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encode(
      swapConfig.maxAmountIn,
      swapConfig.maxExchangeRate,
      swapConfig.exchangeRateDenom,
      swapConfig.nonce,
      swapConfig.expiryTime,
      signature
    );
  }
}
