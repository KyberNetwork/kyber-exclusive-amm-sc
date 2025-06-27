// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import './interfaces/IKEMHookV2.sol';

import './base/BaseKEMHookV2.sol';

import {IHooks} from 'uniswap/v4-core/src/interfaces/IHooks.sol';
import {IPoolManager} from 'uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {IUnlockCallback} from 'uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol';
import {Hooks} from 'uniswap/v4-core/src/libraries/Hooks.sol';

import {IPositionManager} from 'uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {ISubscriber} from 'uniswap/v4-periphery/src/interfaces/ISubscriber.sol';

import {BalanceDelta} from 'uniswap/v4-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta} from 'uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'uniswap/v4-core/src/types/Currency.sol';
import {PoolId} from 'uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from 'uniswap/v4-core/src/types/PoolKey.sol';

import {Position} from 'uniswap/v4-core/src/libraries/Position.sol';
import {StateLibrary} from 'uniswap/v4-core/src/libraries/StateLibrary.sol';
import {
  PositionInfo,
  PositionInfoLibrary
} from 'uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol';

interface IPositionManagerExtended {
  function poolKeys(bytes25 poolId) external view returns (PoolKey memory);
}

/// @title UniswapV4KEMHookV2
contract UniswapV4KEMHookV2 is BaseKEMHookV2, IUnlockCallback, ISubscriber {
  using StateLibrary for IPoolManager;
  using PositionInfoLibrary for PositionInfo;

  /// @notice Thrown when the caller is not PoolManager
  error NotPoolManager();

  /// @notice Thrown when the caller is not PositionManager
  error NotPositionManager();

  /// @notice The address of the PoolManager contract
  IPoolManager public immutable poolManager;

  /// @notice The address of the PositionManager contract
  IPositionManager public immutable positionManager;

  constructor(
    IPositionManager _positionManager,
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialClaimants
  ) BaseKEMHookV2(initialAdmin, initialQuoteSigner, initialEgRecipient, initialClaimants) {
    positionManager = _positionManager;
    poolManager = _positionManager.poolManager();

    Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
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

  /// @notice Only allow calls from the PoolManager contract
  modifier onlyPoolManager() {
    if (msg.sender != address(poolManager)) revert NotPoolManager();
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

    poolManager.unlock(msg.data[4:]);
  }

  /// @inheritdoc IUnlockCallback
  function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
    _claimProtocolEG(data);
  }

  /// @notice Hook function called before a swap
  function beforeSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
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
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
  ) external onlyPoolManager returns (bytes4, int128) {
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

  /// @inheritdoc ISubscriber
  function notifySubscribe(uint256 tokenId, bytes calldata) external onlyPositionManager {
    _notifySubscribe(tokenId);
  }

  /// @inheritdoc ISubscriber
  function notifyUnsubscribe(uint256 tokenId) external onlyPositionManager {
    _notifyUnsubscribe(tokenId);
  }

  /// @inheritdoc ISubscriber
  function notifyBurn(uint256 tokenId, address, PositionInfo info, uint256 liquidity, BalanceDelta)
    external
    onlyPositionManager
  {
    PoolKey memory poolKey =
      IPositionManagerExtended(address(positionManager)).poolKeys(info.poolId());

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

  /// @inheritdoc ISubscriber
  function notifyModifyLiquidity(uint256 tokenId, int256 liquidityDelta, BalanceDelta)
    external
    onlyPositionManager
  {
    _notifyModifyLiquidity(tokenId, liquidityDelta);
  }

  /// @inheritdoc BaseKEMHookV2Accounting
  function _take(address token, address recipient, uint256 amount) internal override {
    poolManager.burn(address(this), uint256(uint160(token)), amount);
    poolManager.take(Currency.wrap(token), recipient, amount);
  }

  /// @inheritdoc BaseKEMHookV2Accounting
  function _settle(address token, address recipient, uint256 amount) internal override {
    Currency currency = Currency.wrap(token);
    poolManager.sync(currency);
    if (currency.isAddressZero()) {
      poolManager.settleFor{value: amount}(recipient);
    } else {
      currency.transfer(address(poolManager), amount);
      poolManager.settleFor(recipient);
    }
  }

  /// @inheritdoc PoolStateView
  function _getSlot0Data(bytes32 poolId) internal view override returns (bytes32) {
    bytes32 stateSlot = StateLibrary._getPoolStateSlot(PoolId.wrap(poolId));
    return poolManager.extsload(stateSlot);
  }

  /// @inheritdoc PoolStateView
  function _getLiquidity(bytes32 poolId) internal view override returns (uint128) {
    return poolManager.getLiquidity(PoolId.wrap(poolId));
  }

  /// @inheritdoc PoolStateView
  function _getTickBitmap(bytes32 poolId, int16 word) internal view override returns (uint256) {
    return poolManager.getTickBitmap(PoolId.wrap(poolId), word);
  }

  /// @inheritdoc PoolStateView
  function _getLiquidityNet(bytes32 poolId, int24 tick)
    internal
    view
    override
    returns (int128 liquidityNet)
  {
    (, liquidityNet) = StateLibrary.getTickLiquidity(poolManager, PoolId.wrap(poolId), tick);
  }

  /// @inheritdoc BaseKEMHookV2Subscriber
  function _getPoolAndPositionInfo(uint256 tokenId)
    internal
    view
    override
    returns (bytes32 poolId, address token0, address token1, int24 tickLower, int24 tickUpper)
  {
    (PoolKey memory poolKey, PositionInfo info) = positionManager.getPoolAndPositionInfo(tokenId);
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
    bytes32 positionId = Position.calculatePositionKey(
      address(positionManager), tickLower, tickUpper, bytes32(tokenId)
    );
    liquidity = poolManager.getPositionLiquidity(PoolId.wrap(poolId), positionId);
  }
}
