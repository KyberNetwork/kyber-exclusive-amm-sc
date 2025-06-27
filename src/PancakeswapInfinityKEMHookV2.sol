// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import './interfaces/IKEMHookV2.sol';

import './base/BaseKEMHookV2.sol';

import {IHooks} from 'pancakeswap/infinity-core/src/interfaces/IHooks.sol';
import {ILockCallback} from 'pancakeswap/infinity-core/src/interfaces/ILockCallback.sol';
import {IVault} from 'pancakeswap/infinity-core/src/interfaces/IVault.sol';
import {ICLPoolManager} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol';

import {ICLPositionManager} from
  'pancakeswap/infinity-periphery/src/pool-cl/interfaces/ICLPositionManager.sol';
import {ICLSubscriber} from
  'pancakeswap/infinity-periphery/src/pool-cl/interfaces/ICLSubscriber.sol';

import {BalanceDelta} from 'pancakeswap/infinity-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta} from 'pancakeswap/infinity-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'pancakeswap/infinity-core/src/types/Currency.sol';
import {PoolId} from 'pancakeswap/infinity-core/src/types/PoolId.sol';
import {PoolKey} from 'pancakeswap/infinity-core/src/types/PoolKey.sol';

import {CLPoolParametersHelper} from
  'pancakeswap/infinity-core/src/pool-cl/libraries/CLPoolParametersHelper.sol';

import {CLPosition} from 'pancakeswap/infinity-core/src/pool-cl/libraries/CLPosition.sol';
import {
  CLPositionInfo,
  CLPositionInfoLibrary
} from 'pancakeswap/infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol';

import {
  HOOKS_AFTER_SWAP_OFFSET,
  HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET,
  HOOKS_BEFORE_SWAP_OFFSET
} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLHooks.sol';

interface ICLPositionManagerExtended {
  function poolKeys(bytes25 poolId) external view returns (PoolKey memory);
}

/// @title PancakeswapInfinityKEMHookV2
contract PancakeswapInfinityKEMHookV2 is BaseKEMHookV2, ILockCallback, IHooks, ICLSubscriber {
  using CLPositionInfoLibrary for CLPositionInfo;

  /// @notice Thrown when the caller is not PoolManager
  error NotPoolManager();

  /// @notice Thrown when the caller is not Vault
  error NotVault();

  /// @notice Thrown when the caller is not PositionManager
  error NotPositionManager();

  /// @notice The address of the CLPoolManager contract
  ICLPoolManager public immutable poolManager;

  /// @notice The address of the Vault contract
  IVault public immutable vault;

  /// @notice The address of the PositionManager contract
  ICLPositionManager public immutable positionManager;

  constructor(
    ICLPositionManager _positionManager,
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialClaimants
  ) BaseKEMHookV2(initialAdmin, initialQuoteSigner, initialEgRecipient, initialClaimants) {
    positionManager = _positionManager;
    poolManager = _positionManager.clPoolManager();
    vault = poolManager.vault();
  }

  /// @inheritdoc IHooks
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

  /// @notice Only allow calls from the PositionManager contract
  modifier onlyPositionManager() {
    if (msg.sender != address(positionManager)) revert NotPositionManager();
    _;
  }

  /// @inheritdoc IKEMHookV2Admin
  function claimProtocolEG(address[] calldata tokens, uint256[] calldata amounts)
    public
    onlyRole(CLAIM_ROLE)
  {
    require(tokens.length == amounts.length, MismatchedArrayLengths());

    vault.lock(msg.data[4:]);
  }

  /// @inheritdoc ILockCallback
  function lockAcquired(bytes calldata data) external onlyVault returns (bytes memory) {
    _claimProtocolEG(data);
  }

  /// @notice Hook function called before a swap
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

  /// @notice Hook function called after a swap
  function afterSwap(
    address,
    PoolKey calldata key,
    ICLPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
  ) external onlyPoolManager returns (bytes4, int128) {
    int24 tickSpacing = CLPoolParametersHelper.getTickSpacing(key.parameters);
    address tokenOut = Currency.unwrap(params.zeroForOne ? key.currency1 : key.currency0);

    uint256 totalEGAmount = _afterSwap(
      PoolId.unwrap(key.toId()),
      tickSpacing,
      tokenOut,
      params.zeroForOne,
      BalanceDelta.unwrap(delta),
      hookData
    );

    return (this.afterSwap.selector, int128(int256(totalEGAmount)));
  }

  /// @inheritdoc ICLSubscriber
  function notifySubscribe(uint256 tokenId, bytes calldata) external onlyPositionManager {
    _notifySubscribe(tokenId);
  }

  /// @inheritdoc ICLSubscriber
  function notifyUnsubscribe(uint256 tokenId) external onlyPositionManager {
    _notifyUnsubscribe(tokenId);
  }

  /// @inheritdoc ICLSubscriber
  function notifyBurn(
    uint256 tokenId,
    address,
    CLPositionInfo info,
    uint256 liquidity,
    BalanceDelta
  ) external onlyPositionManager {
    PoolKey memory poolKey =
      ICLPositionManagerExtended(address(positionManager)).poolKeys(info.poolId());

    _notifyBurn(
      tokenId,
      PoolId.unwrap(poolKey.toId()),
      Currency.unwrap(poolKey.currency0),
      Currency.unwrap(poolKey.currency1),
      info.tickLower(),
      info.tickUpper(),
      liquidity
    );
  }

  /// @inheritdoc ICLSubscriber
  function notifyModifyLiquidity(uint256 tokenId, int256 liquidityDelta, BalanceDelta)
    external
    onlyPositionManager
  {
    _notifyModifyLiquidity(tokenId, liquidityDelta);
  }

  /// @inheritdoc BaseKEMHookV2Accounting
  function _take(address token, address recipient, uint256 amount) internal override {
    Currency currency = Currency.wrap(token);
    vault.burn(address(this), currency, amount);
    vault.take(currency, recipient, amount);
  }

  /// @inheritdoc BaseKEMHookV2Accounting
  function _settle(address token, address recipient, uint256 amount) internal override {
    Currency currency = Currency.wrap(token);
    vault.sync(currency);
    if (currency.isNative()) {
      vault.settleFor{value: amount}(recipient);
    } else {
      currency.transfer(address(vault), amount);
      vault.settleFor(recipient);
    }
  }

  /// @inheritdoc PoolStateView
  function _getSlot0Data(bytes32 poolId) internal view override returns (bytes32) {
    bytes32 stateSlot = keccak256(abi.encodePacked(poolId, bytes32(uint256(4))));
    return poolManager.extsload(stateSlot);
  }

  /// @inheritdoc PoolStateView
  function _getLiquidity(bytes32 poolId) internal view override returns (uint128) {
    return poolManager.getLiquidity(PoolId.wrap(poolId));
  }

  /// @inheritdoc PoolStateView
  function _getTickBitmap(bytes32 poolId, int16 word) internal view override returns (uint256) {
    return poolManager.getPoolBitmapInfo(PoolId.wrap(poolId), word);
  }

  /// @inheritdoc PoolStateView
  function _getLiquidityNet(bytes32 poolId, int24 tick)
    internal
    view
    override
    returns (int128 liquidityNet)
  {
    return poolManager.getPoolTickInfo(PoolId.wrap(poolId), tick).liquidityNet;
  }

  /// @inheritdoc BaseKEMHookV2Subscriber
  function _getPoolAndPositionInfo(uint256 tokenId)
    internal
    view
    override
    returns (bytes32 poolId, address token0, address token1, int24 tickLower, int24 tickUpper)
  {
    (PoolKey memory poolKey, CLPositionInfo info) = positionManager.getPoolAndPositionInfo(tokenId);
    poolId = PoolId.unwrap(poolKey.toId());
    token0 = Currency.unwrap(poolKey.currency0);
    token1 = Currency.unwrap(poolKey.currency1);
    tickLower = info.tickLower();
    tickUpper = info.tickUpper();
  }

  /// @inheritdoc BaseKEMHookV2Subscriber
  function _getPositionLiquidity(uint256 tokenId, bytes32 poolId, int24 tickLower, int24 tickUpper)
    internal
    view
    override
    returns (uint128 liquidity)
  {
    return poolManager.getPosition(
      PoolId.wrap(poolId), address(positionManager), tickLower, tickUpper, bytes32(tokenId)
    ).liquidity;
  }
}
