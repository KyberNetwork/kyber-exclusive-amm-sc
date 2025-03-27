// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IELHook} from './interfaces/IELHook.sol';

import {IPoolManager} from 'uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {Hooks} from 'uniswap/v4-core/src/libraries/Hooks.sol';

import {IUnlockCallback} from 'uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol';
import {BalanceDelta, toBalanceDelta} from 'uniswap/v4-core/src/types/BalanceDelta.sol';
import {
  BeforeSwapDelta, BeforeSwapDeltaLibrary
} from 'uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from 'uniswap/v4-core/src/types/PoolKey.sol';

import {CalldataDecoder} from 'uniswap/v4-periphery/src/libraries/CalldataDecoder.sol';
import {BaseHook} from 'uniswap/v4-periphery/src/utils/BaseHook.sol';

import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

import {KSRescueV2, KyberSwapRole, Ownable} from 'ks-growth-utils-sc/KSRescueV2.sol';

contract UniswapV4ELHook is IELHook, BaseHook, IUnlockCallback, KSRescueV2 {
  /// @inheritdoc IELHook
  mapping(address => bool) public whitelisted;

  /// @inheritdoc IELHook
  address public quoteSigner;

  /// @inheritdoc IELHook
  address public surplusRecipient;

  constructor(
    IPoolManager _poolManager,
    address initialOwner,
    address[] memory initialOperators,
    address initialSigner,
    address initialSurplusRecipient
  ) BaseHook(_poolManager) Ownable(initialOwner) {
    for (uint256 i = 0; i < initialOperators.length; i++) {
      operators[initialOperators[i]] = true;

      emit UpdateOperator(initialOperators[i], true);
    }

    _updateQuoteSigner(initialSigner);
    _updateSurplusRecipient(initialSurplusRecipient);
  }

  /// @inheritdoc IELHook
  function whitelistSenders(address[] calldata senders, bool grantOrRevoke) public onlyOwner {
    for (uint256 i = 0; i < senders.length; i++) {
      whitelisted[senders[i]] = grantOrRevoke;

      emit ELHookWhitelistSender(senders[i], grantOrRevoke);
    }
  }

  /// @inheritdoc IELHook
  function updateQuoteSigner(address newSigner) public onlyOwner {
    _updateQuoteSigner(newSigner);
  }

  /// @inheritdoc IELHook
  function updateSurplusRecipient(address newRecipient) public onlyOwner {
    _updateSurplusRecipient(newRecipient);
  }

  function _updateQuoteSigner(address newSigner) internal {
    require(newSigner != address(0), ELHookInvalidAddress());
    quoteSigner = newSigner;

    emit ELHookUpdateQuoteSigner(newSigner);
  }

  function _updateSurplusRecipient(address newRecipient) internal {
    require(newRecipient != address(0), ELHookInvalidAddress());
    surplusRecipient = newRecipient;

    emit ELHookUpdateSurplusRecipient(newRecipient);
  }

  /// @inheritdoc IELHook
  function claimSurplusTokens(address[] calldata tokens, uint256[] calldata amounts)
    public
    onlyOperator
  {
    require(tokens.length == amounts.length, ELHookMismatchedArrayLengths());

    poolManager.unlock(abi.encode(tokens, amounts));
  }

  function unlockCallback(bytes calldata data) public onlyPoolManager returns (bytes memory) {
    (address[] memory tokens, uint256[] memory amounts) = abi.decode(data, (address[], uint256[]));

    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 id = uint256(uint160(tokens[i]));
      if (amounts[i] == 0) {
        amounts[i] = poolManager.balanceOf(address(this), id);
      }
      if (amounts[i] > 0) {
        poolManager.burn(address(this), id, amounts[i]);
        poolManager.take(Currency.wrap(tokens[i]), surplusRecipient, amounts[i]);
      }
    }

    emit ELHookClaimSurplusTokens(surplusRecipient, tokens, amounts);
  }

  function _beforeSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    bytes calldata hookData
  ) internal view override returns (bytes4, BeforeSwapDelta, uint24) {
    require(whitelisted[sender], ELHookNotWhitelisted(sender));
    require(params.amountSpecified < 0, ELHookExactOutputDisabled());

    (
      int256 maxAmountIn,
      int256 maxExchangeRate,
      int256 exchangeRateDenom,
      uint256 expiryTime,
      bytes memory signature
    ) = _decodeAllHookData(hookData);

    require(block.timestamp <= expiryTime, ELHookExpiredSignature(expiryTime, block.timestamp));
    require(
      -params.amountSpecified <= maxAmountIn,
      ELHookExceededMaxAmountIn(maxAmountIn, -params.amountSpecified)
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
      ELHookInvalidSignature()
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
    (int256 maxExchangeRate, int256 exchangeRateDenom) = _decodeExchangeRate(hookData);

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

      int256 maxAmountOut = amountIn * maxExchangeRate / exchangeRateDenom;
      int256 surplusAmount = maxAmountOut < amountOut ? amountOut - maxAmountOut : int256(0);
      if (surplusAmount > 0) {
        poolManager.mint(
          address(this), uint256(uint160(Currency.unwrap(currencyOut))), uint256(surplusAmount)
        );

        emit ELHookSeizeSurplusToken(key.toId(), Currency.unwrap(currencyOut), surplusAmount);
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

  /// @dev equivalent to: abi.decode(params, (int256, int256, int256, uint256, bytes)) in calldata
  function _decodeAllHookData(bytes calldata hookData)
    internal
    pure
    returns (
      int256 maxAmountIn,
      int256 maxExchangeRate,
      int256 exchangeRateDenom,
      uint256 expiryTime,
      bytes memory signature
    )
  {
    // no length check performed, as there is a length check in `toBytes`
    assembly ("memory-safe") {
      maxAmountIn := calldataload(hookData.offset)
      maxExchangeRate := calldataload(add(hookData.offset, 0x20))
      exchangeRateDenom := calldataload(add(hookData.offset, 0x40))
      expiryTime := calldataload(add(hookData.offset, 0x60))
    }

    signature = CalldataDecoder.toBytes(hookData, 4);
  }

  /// @dev equivalent to: abi.decode(params, (int256, int256, int256, uint256, bytes)) in calldata
  function _decodeExchangeRate(bytes calldata hookData)
    internal
    pure
    returns (int256 maxExchangeRate, int256 exchangeRateDenom)
  {
    assembly ("memory-safe") {
      maxExchangeRate := calldataload(add(hookData.offset, 0x20))
      exchangeRateDenom := calldataload(add(hookData.offset, 0x40))
    }
  }
}
