// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExclusiveLiquidityHook} from './interfaces/IExclusiveLiquidityHook.sol';

import {IPoolManager} from 'uniswap/v4-core/interfaces/IPoolManager.sol';
import {Hooks} from 'uniswap/v4-core/libraries/Hooks.sol';

import {IUnlockCallback} from 'uniswap/v4-core/interfaces/callback/IUnlockCallback.sol';
import {BalanceDelta, toBalanceDelta} from 'uniswap/v4-core/types/BalanceDelta.sol';
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from 'uniswap/v4-core/types/BeforeSwapDelta.sol';
import {Currency} from 'uniswap/v4-core/types/Currency.sol';
import {PoolKey} from 'uniswap/v4-core/types/PoolKey.sol';
import {BaseHook} from 'uniswap/v4-periphery/utils/BaseHook.sol';

import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

import {KSRescueV2, Ownable} from 'ks-growth-utils-sc/KSRescueV2.sol';

contract UniswapV4ExclusiveLiquidityHook is
  IExclusiveLiquidityHook,
  BaseHook,
  IUnlockCallback,
  KSRescueV2
{
  int256 internal constant EXCHANGE_RATE_DENOMINATOR = 1e18;

  mapping(address => bool) public routers;

  address surplusRecipient;

  constructor(
    IPoolManager _poolManager,
    address initialOwner,
    address[] memory initialOperators,
    address[] memory initialGuardians
  ) BaseHook(_poolManager) Ownable(initialOwner) {
    for (uint256 i = 0; i < initialOperators.length; i++) {
      operators[initialOperators[i]] = true;

      emit UpdateOperator(initialOperators[i], true);
    }
    for (uint256 i = 0; i < initialGuardians.length; i++) {
      guardians[initialGuardians[i]] = true;

      emit UpdateGuardian(initialGuardians[i], true);
    }
  }

  function updateRouter(address router, bool grantOrRevoke) external onlyOwner {
    routers[router] = grantOrRevoke;

    emit UpdateRouter(router, grantOrRevoke);
  }

  function updateSurplusRecipient(address recipient) external onlyOwner {
    require(recipient != address(0), InvalidSurplusRecipient());
    surplusRecipient = recipient;
  }

  function _beforeSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    bytes calldata hookData
  ) internal view override returns (bytes4, BeforeSwapDelta, uint24) {
    require(routers[sender], KSHookNotRouter(sender));
    require(params.amountSpecified < 0, KSHookExactOutputDisabled());
    (
      int256 maxAmountIn,
      int256 maxExchangeRate,
      uint256 expiryTime,
      address operator,
      bytes memory signature
    ) = abi.decode(hookData, (int256, int256, uint256, address, bytes));
    require(block.timestamp <= expiryTime, KSHookExpiredSignature());
    require(
      SignatureChecker.isValidSignatureNow(
        operator,
        keccak256(abi.encode(key, params.zeroForOne, maxAmountIn, maxExchangeRate, expiryTime)),
        signature
      ),
      KSHookInvalidSignature()
    );
    return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
  }

  function _afterSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
  ) internal override returns (bytes4, int128) {
    (int256 maxAmountIn, int256 maxExchangeRate,,,) =
      abi.decode(hookData, (int256, int256, uint256, address, bytes));

    unchecked {
      int128 amountIn;
      int128 amountOut;
      Currency currencyOut;
      if (params.zeroForOne) {
        amountIn = -delta.amount0();
        amountOut = delta.amount1();
        currencyOut = key.currency1;
      } else {
        amountIn = -delta.amount1();
        amountOut = delta.amount0();
        currencyOut = key.currency0;
      }
      require(amountIn <= maxAmountIn, ExceededMaxAmountIn());

      int256 maxAmountOut = amountIn * maxExchangeRate / EXCHANGE_RATE_DENOMINATOR;
      int256 surplusAmount = maxAmountOut < amountOut ? amountOut - maxAmountOut : int256(0);
      if (surplusAmount > 0) {
        poolManager.mint(
          address(this), uint256(uint160(Currency.unwrap(currencyOut))), uint256(surplusAmount)
        );
      }

      return (this.afterSwap.selector, int128(surplusAmount));
    }
  }

  function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
      beforeInitialize: false,
      afterInitialize: false,
      beforeAddLiquidity: false,
      afterAddLiquidity: false,
      beforeRemoveLiquidity: false,
      afterRemoveLiquidity: false,
      beforeSwap: true,
      afterSwap: true,
      beforeDonate: false,
      afterDonate: false,
      beforeSwapReturnDelta: false,
      afterSwapReturnDelta: true,
      afterAddLiquidityReturnDelta: false,
      afterRemoveLiquidityReturnDelta: false
    });
  }

  /// @inheritdoc IExclusiveLiquidityHook
  function claimSurplusTokens(uint256[] calldata ids) public onlyOperator {
    poolManager.unlock(abi.encode(ids));
  }

  function unlockCallback(bytes calldata data) external returns (bytes memory) {
    uint256[] memory ids = abi.decode(data, (uint256[]));

    for (uint256 i = 0; i < ids.length; i++) {
      uint256 id = ids[i];
      uint256 balance = poolManager.balanceOf(address(this), id);
      if (balance > 0) {
        poolManager.burn(address(this), id, balance);
        poolManager.take(Currency.wrap(address(uint160(id))), surplusRecipient, balance);
      }
    }
  }
}
