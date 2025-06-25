// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseKEMHookV2} from './base/BaseKEMHookV2.sol';
import './interfaces/IKEMHookV2.sol';

import {IPoolManager} from 'uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {IUnlockCallback} from 'uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol';
import {Hooks} from 'uniswap/v4-core/src/libraries/Hooks.sol';

import {BalanceDelta} from 'uniswap/v4-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta} from 'uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from 'uniswap/v4-core/src/types/Currency.sol';
import {PoolId} from 'uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from 'uniswap/v4-core/src/types/PoolKey.sol';

/// @title UniswapV4KEMHookV2
contract UniswapV4KEMHookV2 is BaseKEMHookV2, IUnlockCallback {
  /// @notice Thrown when the caller is not PoolManager
  error NotPoolManager();

  /// @notice The address of the PoolManager contract
  IPoolManager public immutable poolManager;

  constructor(
    IPoolManager _poolManager,
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialClaimants
  ) BaseKEMHookV2(initialAdmin, initialQuoteSigner, initialEgRecipient, initialClaimants) {
    poolManager = _poolManager;
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

  /// @inheritdoc IKEMHookV2Admin
  function claimProtocolEG(address[] calldata tokens, uint256[] calldata amounts)
    public
    onlyRole(CLAIM_ROLE)
  {
    require(tokens.length == amounts.length, MismatchedArrayLengths());

    poolManager.unlock(abi.encode(tokens, amounts));
  }

  /// @inheritdoc IKEMHookV2Actions
  function claimPositionEG(uint256 tokenId) public {}

  /// @inheritdoc IUnlockCallback
  function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
    (address[] memory tokens, uint256[] memory amounts) = abi.decode(data, (address[], uint256[]));
    address _egRecipient = egRecipient;

    for (uint256 i = 0; i < tokens.length; i++) {
      address token = tokens[i];
      uint256 id = uint256(uint160(token));

      uint256 amount = amounts[i];
      if (amount == 0) {
        amount = protocolEGAmountOf[token];
      }

      if (amount > 0) {
        amounts[i] = amount;
        protocolEGAmountOf[token] -= amount;
        poolManager.burn(address(this), id, amount);
        poolManager.take(Currency.wrap(token), _egRecipient, amount);
      }
    }

    emit ClaimProtocolEG(_egRecipient, tokens, amounts);
  }

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

  function afterSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
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
