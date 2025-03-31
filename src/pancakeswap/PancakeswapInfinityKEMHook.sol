// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseKEMHook} from '../BaseKEMHook.sol';

import {IKEMHook} from '../interfaces/IKEMHook.sol';
import {HookDataDecoder} from '../libraries/HookDataDecoder.sol';
import {BaseCLHook} from './BaseCLHook.sol';

import {ICLPoolManager} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol';

import {BalanceDelta} from 'pancakeswap/infinity-core/src/types/BalanceDelta.sol';
import {
  BeforeSwapDelta,
  BeforeSwapDeltaLibrary
} from 'pancakeswap/infinity-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'pancakeswap/infinity-core/src/types/Currency.sol';
import {PoolId} from 'pancakeswap/infinity-core/src/types/PoolId.sol';
import {PoolKey} from 'pancakeswap/infinity-core/src/types/PoolKey.sol';

import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

/// @title PancakeSwapInfinityKEMHook
contract PancakeSwapInfinityKEMHook is BaseCLHook, BaseKEMHook {
  constructor(
    ICLPoolManager _poolManager,
    address initialAdmin,
    address initialQuoteSigner,
    address initialEGRecipient
  ) BaseCLHook(_poolManager) BaseKEMHook(initialAdmin, initialQuoteSigner, initialEGRecipient) {}

  /// @inheritdoc IKEMHook
  function claimEgTokens(address[] calldata tokens, uint256[] calldata amounts)
    public
    onlyRole(CLAIM_ROLE)
  {
    require(tokens.length == amounts.length, MismatchedArrayLengths());

    vault.lock(abi.encode(tokens, amounts));
  }

  function lockAcquired(bytes calldata data) public override vaultOnly returns (bytes memory) {
    (address[] memory tokens, uint256[] memory amounts) = abi.decode(data, (address[], uint256[]));

    for (uint256 i = 0; i < tokens.length; i++) {
      Currency currency = Currency.wrap(tokens[i]);
      if (amounts[i] == 0) {
        amounts[i] = vault.balanceOf(address(this), currency);
      }
      if (amounts[i] > 0) {
        vault.burn(address(this), currency, amounts[i]);
        vault.take(currency, egRecipient, amounts[i]);
      }
    }

    emit ClaimEgTokens(egRecipient, tokens, amounts);
  }

  function getHooksRegistrationBitmap() external pure override returns (uint16) {
    return _hooksRegistrationBitmapFrom(
      Permissions({
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
      })
    );
  }

  function _beforeSwap(
    address sender,
    PoolKey calldata key,
    ICLPoolManager.SwapParams calldata params,
    bytes calldata hookData
  ) internal view override returns (bytes4, BeforeSwapDelta, uint24) {
    _checkRole(SWAP_ROLE, sender);
    require(params.amountSpecified < 0, ExactOutputDisabled());

    (
      int256 maxAmountIn,
      int256 maxExchangeRate,
      int256 exchangeRateDenom,
      uint256 expiryTime,
      bytes memory signature
    ) = HookDataDecoder.decodeAllHookData(hookData);

    require(block.timestamp <= expiryTime, ExpiredSignature(expiryTime, block.timestamp));
    require(
      -params.amountSpecified <= maxAmountIn,
      ExceededMaxAmountIn(maxAmountIn, -params.amountSpecified)
    );
    require(
      SignatureChecker.isValidSignatureNow(
        quoteSigner,
        keccak256(
          abi.encode(
            key, params.zeroForOne, maxAmountIn, maxExchangeRate, exchangeRateDenom, expiryTime
          )
        ),
        signature
      ),
      InvalidSignature()
    );

    return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
  }

  function _afterSwap(
    address,
    PoolKey calldata key,
    ICLPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
  ) internal override returns (bytes4, int128) {
    (int256 maxExchangeRate, int256 exchangeRateDenom) =
      HookDataDecoder.decodeExchangeRate(hookData);

    int128 amountIn;
    int128 amountOut;
    Currency currencyOut;
    unchecked {
      if (params.zeroForOne) {
        amountIn = -delta.amount0();
        amountOut = delta.amount1();
        currencyOut = key.currency1;
      } else {
        amountIn = -delta.amount1();
        amountOut = delta.amount0();
        currencyOut = key.currency0;
      }
    }

    int256 maxAmountOut = amountIn * maxExchangeRate / exchangeRateDenom;

    unchecked {
      int256 egAmount = maxAmountOut < amountOut ? amountOut - maxAmountOut : int256(0);
      if (egAmount > 0) {
        vault.mint(address(this), currencyOut, uint256(egAmount));

        emit AbsorbEgToken(PoolId.unwrap(key.toId()), Currency.unwrap(currencyOut), egAmount);
      }

      return (this.afterSwap.selector, int128(egAmount));
    }
  }
}
