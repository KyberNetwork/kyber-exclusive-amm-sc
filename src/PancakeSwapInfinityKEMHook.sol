// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseKEMHook} from './base/BaseKEMHook.sol';

import {IKEMHook} from './interfaces/IKEMHook.sol';
import {HookDataDecoder} from './libraries/HookDataDecoder.sol';

import {IVault} from 'pancakeswap/infinity-core/src/interfaces/IVault.sol';
import {ICLPoolManager} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol';

import {BalanceDelta} from 'pancakeswap/infinity-core/src/types/BalanceDelta.sol';
import {
  BeforeSwapDelta,
  BeforeSwapDeltaLibrary
} from 'pancakeswap/infinity-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'pancakeswap/infinity-core/src/types/Currency.sol';
import {PoolId} from 'pancakeswap/infinity-core/src/types/PoolId.sol';
import {PoolKey} from 'pancakeswap/infinity-core/src/types/PoolKey.sol';

import {
  HOOKS_AFTER_SWAP_OFFSET,
  HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET,
  HOOKS_BEFORE_SWAP_OFFSET
} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLHooks.sol';

import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

/// @title PancakeSwapInfinityKEMHook
contract PancakeSwapInfinityKEMHook is BaseKEMHook {
  /// @notice Thrown when the caller is not PoolManager
  error NotPoolManager();

  /// @notice Thrown when the caller is not Vault
  error NotVault();

  /// @notice The address of the PoolManager contract
  ICLPoolManager public immutable poolManager;

  /// @notice The address of the Vault contract
  IVault public immutable vault;

  constructor(
    ICLPoolManager _poolManager,
    address initialOwner,
    address[] memory initialClaimableAccounts,
    address[] memory initialWhitelistedAccounts,
    address initialQuoteSigner,
    address initialEgRecipient
  )
    BaseKEMHook(
      initialOwner,
      initialClaimableAccounts,
      initialWhitelistedAccounts,
      initialQuoteSigner,
      initialEgRecipient
    )
  {
    poolManager = _poolManager;
    vault = _poolManager.vault();
  }

  /// @notice Only allow calls from the PoolManager contract
  modifier onlyPoolManager() {
    if (msg.sender != address(poolManager)) revert NotPoolManager();
    _;
  }

  /// @notice Only allow calls from the Vault contract
  modifier onlyVault() {
    if (msg.sender != address(vault)) revert NotVault();
    _;
  }

  /// @inheritdoc IKEMHook
  function claimEgTokens(address[] calldata tokens, uint256[] calldata amounts) public {
    require(claimable[msg.sender], NonClaimableAccount(msg.sender));
    require(tokens.length == amounts.length, MismatchedArrayLengths());

    vault.lock(abi.encode(tokens, amounts));
  }

  function lockAcquired(bytes calldata data) public onlyVault returns (bytes memory) {
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

  function getHooksRegistrationBitmap() external pure returns (uint16) {
    return uint16(
      (1 << HOOKS_BEFORE_SWAP_OFFSET) | (1 << HOOKS_AFTER_SWAP_OFFSET)
        | (1 << HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET)
    );
  }

  function beforeSwap(
    address sender,
    PoolKey calldata key,
    ICLPoolManager.SwapParams calldata params,
    bytes calldata hookData
  ) external view onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
    require(whitelisted[sender], NonWhitelistedAccount(sender));
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

  function afterSwap(
    address,
    PoolKey calldata key,
    ICLPoolManager.SwapParams calldata params,
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
        vault.mint(address(this), currencyOut, uint256(egAmount));

        emit AbsorbEgToken(PoolId.unwrap(key.toId()), Currency.unwrap(currencyOut), egAmount);
      }

      return (this.afterSwap.selector, int128(egAmount));
    }
  }
}
