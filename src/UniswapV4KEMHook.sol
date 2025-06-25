// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseKEMHook} from './base/BaseKEMHook.sol';
import {IKEMHook} from './interfaces/IKEMHook.sol';
import {HookDataDecoder} from './libraries/HookDataDecoder.sol';

import {IHooks} from 'uniswap/v4-core/src/interfaces/IHooks.sol';
import {IPoolManager} from 'uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {IUnlockCallback} from 'uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol';
import {Hooks} from 'uniswap/v4-core/src/libraries/Hooks.sol';

import {BalanceDelta, toBalanceDelta} from 'uniswap/v4-core/src/types/BalanceDelta.sol';
import {
  BeforeSwapDelta, BeforeSwapDeltaLibrary
} from 'uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'uniswap/v4-core/src/types/Currency.sol';
import {PoolId} from 'uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from 'uniswap/v4-core/src/types/PoolKey.sol';

import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

/// @title UniswapV4KEMHook
contract UniswapV4KEMHook is BaseKEMHook, IUnlockCallback {
  /// @notice Thrown when the caller is not PoolManager
  error NotPoolManager();

  /// @notice The address of the PoolManager contract
  IPoolManager public immutable poolManager;

  constructor(
    IPoolManager _poolManager,
    address initialOwner,
    address[] memory initialClaimableAccounts,
    address initialQuoteSigner,
    address initialEgRecipient
  ) BaseKEMHook(initialOwner, initialClaimableAccounts, initialQuoteSigner, initialEgRecipient) {
    poolManager = _poolManager;
    Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
  }

  /// @notice Only allow calls from the PoolManager contract
  modifier onlyPoolManager() {
    if (msg.sender != address(poolManager)) revert NotPoolManager();
    _;
  }

  /// @inheritdoc IKEMHook
  function claimEgTokens(address[] calldata tokens, uint256[] calldata amounts) public {
    require(claimable[msg.sender], NonClaimableAccount(msg.sender));
    require(tokens.length == amounts.length, MismatchedArrayLengths());

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
        poolManager.take(Currency.wrap(tokens[i]), egRecipient, amounts[i]);
      }
    }

    emit ClaimEgTokens(egRecipient, tokens, amounts);
  }

  function getHookPermissions() public pure returns (Hooks.Permissions memory) {
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

  function beforeSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    bytes calldata hookData
  ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
    require(params.amountSpecified < 0, ExactOutputDisabled());

    (
      int256 maxAmountIn,
      int256 maxExchangeRate,
      int256 exchangeRateDenom,
      uint256 nonce,
      uint256 expiryTime,
      bytes memory signature
    ) = HookDataDecoder.decodeAllHookData(hookData);

    require(block.timestamp <= expiryTime, ExpiredSignature(expiryTime, block.timestamp));
    require(
      -params.amountSpecified <= maxAmountIn,
      ExceededMaxAmountIn(maxAmountIn, -params.amountSpecified)
    );

    _useUnorderedNonce(nonce);

    bytes32 digest = keccak256(
      abi.encode(
        sender,
        key,
        params.zeroForOne,
        maxAmountIn,
        maxExchangeRate,
        exchangeRateDenom,
        nonce,
        expiryTime
      )
    );
    require(
      SignatureChecker.isValidSignatureNow(quoteSigner, digest, signature), InvalidSignature()
    );

    return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
  }

  function afterSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
  ) external onlyPoolManager returns (bytes4, int128) {
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
        poolManager.mint(
          address(this), uint256(uint160(Currency.unwrap(currencyOut))), uint256(egAmount)
        );

        emit AbsorbEgToken(PoolId.unwrap(key.toId()), Currency.unwrap(currencyOut), egAmount);
      }

      return (this.afterSwap.selector, int128(egAmount));
    }
  }
}
