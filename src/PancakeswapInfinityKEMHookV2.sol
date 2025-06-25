// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseKEMHookV2} from './base/BaseKEMHookV2.sol';
import './interfaces/IKEMHookV2.sol';

import {ILockCallback} from 'pancakeswap/infinity-core/src/interfaces/ILockCallback.sol';
import {IVault} from 'pancakeswap/infinity-core/src/interfaces/IVault.sol';
import {ICLPoolManager} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol';

import {BalanceDelta} from 'pancakeswap/infinity-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta} from 'pancakeswap/infinity-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'pancakeswap/infinity-core/src/types/Currency.sol';
import {PoolId} from 'pancakeswap/infinity-core/src/types/PoolId.sol';
import {PoolKey} from 'pancakeswap/infinity-core/src/types/PoolKey.sol';

import {
  HOOKS_AFTER_SWAP_OFFSET,
  HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET,
  HOOKS_BEFORE_SWAP_OFFSET
} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLHooks.sol';

/// @title PancakeswapInfinityKEMHookV2
contract PancakeswapInfinityKEMHookV2 is BaseKEMHookV2, ILockCallback {
  /// @notice Thrown when the caller is not PoolManager
  error NotPoolManager();

  /// @notice Thrown when the caller is not Vault
  error NotVault();

  /// @notice The address of the CLPoolManager contract
  ICLPoolManager public immutable poolManager;

  /// @notice The address of the Vault contract
  IVault public immutable vault;

  constructor(
    ICLPoolManager _poolManager,
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialClaimants
  ) BaseKEMHookV2(initialAdmin, initialQuoteSigner, initialEgRecipient, initialClaimants) {
    poolManager = _poolManager;
    vault = _poolManager.vault();
  }

  function getHooksRegistrationBitmap() external pure returns (uint16) {
    return uint16(
      (1 << HOOKS_BEFORE_SWAP_OFFSET) | (1 << HOOKS_AFTER_SWAP_OFFSET)
        | (1 << HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET)
    );
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

  /// @inheritdoc IKEMHookV2Admin
  function claimProtocolEG(address[] calldata tokens, uint256[] calldata amounts)
    public
    onlyRole(CLAIM_ROLE)
  {
    require(tokens.length == amounts.length, MismatchedArrayLengths());

    vault.lock(abi.encode(tokens, amounts));
  }

  /// @inheritdoc IKEMHookV2Actions
  function claimPositionEG(uint256 tokenId) public {}

  /// @inheritdoc ILockCallback
  function lockAcquired(bytes calldata data) external onlyVault returns (bytes memory) {
    (address[] memory tokens, uint256[] memory amounts) = abi.decode(data, (address[], uint256[]));
    address _egRecipient = egRecipient;

    for (uint256 i = 0; i < tokens.length; i++) {
      address token = tokens[i];

      uint256 amount = amounts[i];
      if (amount == 0) {
        amount = protocolEGAmountOf[token];
      }

      if (amount > 0) {
        amounts[i] = amount;
        protocolEGAmountOf[token] -= amount;
        vault.burn(address(this), Currency.wrap(token), amount);
        vault.take(Currency.wrap(token), _egRecipient, amount);
      }
    }

    emit ClaimProtocolEG(_egRecipient, tokens, amounts);
  }

  function beforeSwap(
    address sender,
    PoolKey calldata key,
    ICLPoolManager.SwapParams calldata params,
    bytes calldata hookData
  ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
    _beforeSwap(
      sender, PoolId.unwrap(key.toId()), params.zeroForOne, params.amountSpecified, hookData
    );

    return (this.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
  }

  function afterSwap(
    address,
    PoolKey calldata key,
    ICLPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
  ) external onlyPoolManager returns (bytes4, int128) {
    address tokenOut = Currency.unwrap(params.zeroForOne ? key.currency1 : key.currency0);
    int256 totalEGAmount = _afterSwap(
      PoolId.unwrap(key.toId()), tokenOut, params.zeroForOne, BalanceDelta.unwrap(delta), hookData
    );

    return (this.afterSwap.selector, int128(totalEGAmount));
  }
}
