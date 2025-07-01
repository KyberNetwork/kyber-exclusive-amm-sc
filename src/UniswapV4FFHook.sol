// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import './interfaces/IFFHook.sol';
import {IPoolManager} from 'uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {IUnlockCallback} from 'uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol';
import {Hooks} from 'uniswap/v4-core/src/libraries/Hooks.sol';

import './BaseFFHook.sol';
import {BaseHook} from 'uniswap/v4-periphery/src/utils/BaseHook.sol';

import {BalanceDelta, toBalanceDelta} from 'uniswap/v4-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta} from 'uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'uniswap/v4-core/src/types/Currency.sol';
import {PoolId} from 'uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from 'uniswap/v4-core/src/types/PoolKey.sol';
import {ModifyLiquidityParams, SwapParams} from 'uniswap/v4-core/src/types/PoolOperation.sol';

import {Position} from 'uniswap/v4-core/src/libraries/Position.sol';
import {StateLibrary} from 'uniswap/v4-core/src/libraries/StateLibrary.sol';

/// @title UniswapV4FFHook
/// @notice Uniswap V4 variant of the FFHook
contract UniswapV4FFHook is BaseFFHook, BaseHook, IUnlockCallback {
  using StateLibrary for IPoolManager;

  constructor(
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address[] memory initialRescuers,
    IPoolManager _poolManager
  )
    FFHookAdmin(
      initialAdmin,
      initialQuoteSigner,
      initialEgRecipient,
      initialOperators,
      initialGuardians,
      initialRescuers
    )
    BaseHook(_poolManager)
  {}

  /// @inheritdoc BaseHook
  function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
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
    });
  }

  /// @inheritdoc IUnlockCallback
  function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
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
    ModifyLiquidityParams calldata params,
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
    ModifyLiquidityParams calldata params,
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
    SwapParams calldata params,
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
    SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
  ) internal override returns (bytes4, int128) {
    // make sure that if the hook is paused, all the pools will be have like a normal pool
    if (paused()) {
      return (this.afterSwap.selector, 0);
    }

    address tokenOut = Currency.unwrap(params.zeroForOne ? key.currency1 : key.currency0);

    uint256 totalEGAmount = _afterSwap(
      PoolId.unwrap(key.toId()),
      key.tickSpacing,
      tokenOut,
      params.zeroForOne,
      BalanceDelta.unwrap(delta),
      hookData
    );

    return (this.afterSwap.selector, int128(int256(totalEGAmount)));
  }

  /// @inheritdoc FFHookAccounting
  function _lockOrUnlock(bytes memory data) internal override {
    poolManager.unlock(data);
  }

  /// @inheritdoc FFHookAccounting
  function _burn(address token, uint256 amount) internal override {
    poolManager.burn(address(this), uint256(uint160(token)), amount);
  }

  /// @inheritdoc FFHookAccounting
  function _mint(address token, uint256 amount) internal override {
    poolManager.mint(address(this), uint256(uint160(token)), amount);
  }

  /// @inheritdoc FFHookAccounting
  function _take(address token, address recipient, uint256 amount) internal override {
    poolManager.take(Currency.wrap(token), recipient, amount);
  }

  /// @inheritdoc FFHookAccounting
  function _getTotalEGUnclaimed(address token) internal view override returns (uint256) {
    return poolManager.balanceOf(address(this), uint256(uint160(token)));
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
    return poolManager.getTickBitmap(PoolId.wrap(poolId), word);
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
    bytes32 positionId = Position.calculatePositionKey(owner, tickLower, tickUpper, salt);
    return poolManager.getPositionLiquidity(PoolId.wrap(poolId), positionId);
  }
}
