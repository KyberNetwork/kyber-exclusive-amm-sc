// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import './interfaces/IFFHook.sol';
import {IHooks} from 'pancakeswap/infinity-core/src/interfaces/IHooks.sol';
import {ILockCallback} from 'pancakeswap/infinity-core/src/interfaces/ILockCallback.sol';
import {ICLPoolManager} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol';

import './BaseFFHook.sol';
import {CLBaseHook} from './pancakeswap/CLBaseHook.sol';

import {BalanceDelta, toBalanceDelta} from 'pancakeswap/infinity-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta} from 'pancakeswap/infinity-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'pancakeswap/infinity-core/src/types/Currency.sol';
import {PoolId} from 'pancakeswap/infinity-core/src/types/PoolId.sol';
import {PoolKey} from 'pancakeswap/infinity-core/src/types/PoolKey.sol';

import {StateLibrary} from './pancakeswap/StateLibrary.sol';
import {CLPoolParametersHelper} from
  'pancakeswap/infinity-core/src/pool-cl/libraries/CLPoolParametersHelper.sol';
import {CLPosition} from 'pancakeswap/infinity-core/src/pool-cl/libraries/CLPosition.sol';

/// @title PancakeSwapInfinityFFHook
/// @notice PancakeSwap Infinity variant of the FFHook
contract PancakeSwapInfinityFFHook is BaseFFHook, CLBaseHook, ILockCallback {
  using CLPoolParametersHelper for bytes32;
  using StateLibrary for ICLPoolManager;

  constructor(
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address[] memory initialRescuers,
    ICLPoolManager _poolManager
  )
    FFHookAdmin(
      initialAdmin,
      initialQuoteSigner,
      initialEgRecipient,
      initialOperators,
      initialGuardians,
      initialRescuers
    )
    CLBaseHook(_poolManager)
  {}

  /// @inheritdoc IHooks
  function getHooksRegistrationBitmap() external pure returns (uint16) {
    return _hooksRegistrationBitmapFrom(
      Permissions({
        beforeInitialize: true,
        afterInitialize: false,
        beforeAddLiquidity: false,
        afterAddLiquidity: true,
        beforeRemoveLiquidity: false,
        afterRemoveLiquidity: true,
        beforeSwap: true,
        afterSwap: true,
        beforeDonate: false,
        afterDonate: false,
        beforeSwapReturnDelta: false,
        afterSwapReturnDelta: true,
        afterAddLiquidityReturnDelta: true,
        afterRemoveLiquidityReturnDelta: true
      })
    );
  }

  /// @inheritdoc ILockCallback
  function lockAcquired(bytes calldata data) external vaultOnly returns (bytes memory) {
    _burnAndTakeEGs(data, egRecipient);

    return '';
  }

  /// @notice Stop the pool from being initialized if the hook is paused
  function _beforeInitialize(address, PoolKey calldata, uint160)
    internal
    override
    whenNotPaused
    returns (bytes4)
  {
    return this.beforeInitialize.selector;
  }

  function _afterAddLiquidity(
    address sender,
    PoolKey calldata key,
    ICLPoolManager.ModifyLiquidityParams calldata params,
    BalanceDelta, /* delta **/
    BalanceDelta, /* feesAccrued **/
    bytes calldata /* hookData **/
  ) internal override returns (bytes4, BalanceDelta) {
    // make sure that if the hook is paused, all the pools will be have like a normal pool
    if (paused()) {
      return (this.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    int256 hookDelta = _afterModifyLiquidity(
      PoolId.unwrap(key.toId()),
      Currency.unwrap(key.currency0),
      Currency.unwrap(key.currency1),
      sender,
      params.tickLower,
      params.tickUpper,
      params.salt,
      int128(params.liquidityDelta)
    );

    return (this.afterAddLiquidity.selector, BalanceDelta.wrap(hookDelta));
  }

  function _afterRemoveLiquidity(
    address sender,
    PoolKey calldata key,
    ICLPoolManager.ModifyLiquidityParams calldata params,
    BalanceDelta, /* delta **/
    BalanceDelta, /* feesAccrued **/
    bytes calldata /* hookData **/
  ) internal override returns (bytes4, BalanceDelta) {
    // make sure that if the hook is paused, all the pools will be have like a normal pool
    if (paused()) {
      return (this.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    int256 hookDelta = _afterModifyLiquidity(
      PoolId.unwrap(key.toId()),
      Currency.unwrap(key.currency0),
      Currency.unwrap(key.currency1),
      sender,
      params.tickLower,
      params.tickUpper,
      params.salt,
      int128(params.liquidityDelta)
    );

    return (this.afterRemoveLiquidity.selector, BalanceDelta.wrap(hookDelta));
  }

  function _beforeSwap(
    address sender,
    PoolKey calldata key,
    ICLPoolManager.SwapParams calldata params,
    bytes calldata hookData
  ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
    // make sure that if the hook is paused, all the pools will be have like a normal pool
    if (!paused()) {
      _beforeSwap(
        sender, PoolId.unwrap(key.toId()), params.zeroForOne, params.amountSpecified, hookData
      );
    }

    return (this.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
  }

  function _afterSwap(
    address, /* sender **/
    PoolKey calldata key,
    ICLPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
  ) internal override returns (bytes4, int128) {
    // make sure that if the hook is paused, all the pools will be have like a normal pool
    if (paused()) {
      return (this.afterSwap.selector, 0);
    }

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

  /// @inheritdoc FFHookAccounting
  function _lockOrUnlock(bytes memory data) internal override {
    vault.lock(data);
  }

  /// @inheritdoc FFHookAccounting
  function _burn(address token, uint256 amount) internal override {
    vault.burn(address(this), Currency.wrap(token), amount);
  }

  /// @inheritdoc FFHookAccounting
  function _mint(address token, uint256 amount) internal override {
    vault.mint(address(this), Currency.wrap(token), amount);
  }

  /// @inheritdoc FFHookAccounting
  function _take(address token, address recipient, uint256 amount) internal override {
    vault.take(Currency.wrap(token), recipient, amount);
  }

  /// @inheritdoc FFHookAccounting
  function _getTotalEGUnclaimed(address token) internal view override returns (uint256) {
    return vault.balanceOf(address(this), Currency.wrap(token));
  }

  /// @inheritdoc FFHookStateView
  function _getSlot0Data(bytes32 poolId) internal view override returns (bytes32) {
    bytes32 stateSlot = StateLibrary._getPoolStateSlot(PoolId.wrap(poolId));
    return poolManager.extsload(stateSlot);
  }

  /// @inheritdoc FFHookStateView
  function _getLiquidity(bytes32 poolId) internal view override returns (uint128) {
    return poolManager.getLiquidity(PoolId.wrap(poolId));
  }

  /// @inheritdoc FFHookStateView
  function _getTickBitmap(bytes32 poolId, int16 word) internal view override returns (uint256) {
    return poolManager.getPoolBitmapInfo(PoolId.wrap(poolId), word);
  }

  /// @inheritdoc FFHookStateView
  function _getTickLiquidity(bytes32 poolId, int24 tick)
    internal
    view
    override
    returns (uint128, int128)
  {
    return StateLibrary.getTickLiquidity(poolManager, PoolId.wrap(poolId), tick);
  }

  /// @inheritdoc FFHookStateView
  function _getPositionLiquidity(
    bytes32 poolId,
    address owner,
    int24 tickLower,
    int24 tickUpper,
    bytes32 salt
  ) internal view override returns (uint128) {
    bytes32 positionId = CLPosition.calculatePositionKey(owner, tickLower, tickUpper, salt);
    return poolManager.getPositionLiquidity(PoolId.wrap(poolId), positionId);
  }
}
