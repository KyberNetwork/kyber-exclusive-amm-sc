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
import {BaseHook} from 'uniswap/v4-periphery/src/utils/BaseHook.sol';

import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

import {KSRescueV2, KyberSwapRole, Ownable} from 'ks-growth-utils-sc/KSRescueV2.sol';

contract UniswapV4ELHook is IELHook, BaseHook, IUnlockCallback, KSRescueV2 {
  mapping(address => bool) public whitelisted;

  address public surplusRecipient;

  constructor(
    IPoolManager _poolManager,
    address initialOwner,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address initialRecipient
  ) BaseHook(_poolManager) Ownable(initialOwner) {
    for (uint256 i = 0; i < initialOperators.length; i++) {
      operators[initialOperators[i]] = true;

      emit UpdateOperator(initialOperators[i], true);
    }
    for (uint256 i = 0; i < initialGuardians.length; i++) {
      guardians[initialGuardians[i]] = true;

      emit UpdateGuardian(initialGuardians[i], true);
    }

    _updateSurplusRecipient(initialRecipient);
  }

  /// @inheritdoc IELHook
  function updateWhitelist(address sender, bool grantOrRevoke) external onlyOwner {
    whitelisted[sender] = grantOrRevoke;

    emit KSHookUpdateWhitelisted(sender, grantOrRevoke);
  }

  /// @inheritdoc IELHook
  function updateSurplusRecipient(address recipient) external onlyOwner {
    _updateSurplusRecipient(recipient);
  }

  function _updateSurplusRecipient(address recipient) internal {
    require(recipient != address(0), KSHookInvalidSurplusRecipient());
    surplusRecipient = recipient;

    emit KSHookUpdateSurplusRecipient(recipient);
  }

  /// @inheritdoc IELHook
  function claimSurplusTokens(address[] calldata tokens) public onlyOperator {
    poolManager.unlock(abi.encode(tokens));
  }

  function unlockCallback(bytes calldata data) external returns (bytes memory) {
    address[] memory tokens = abi.decode(data, (address[]));
    uint256[] memory amounts = new uint256[](tokens.length);

    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 id = uint256(uint160(tokens[i]));
      amounts[i] = poolManager.balanceOf(address(this), id);
      if (amounts[i] > 0) {
        poolManager.burn(address(this), id, amounts[i]);
        poolManager.take(Currency.wrap(tokens[i]), surplusRecipient, amounts[i]);
      }
    }

    emit KSHookClaimSurplusTokens(tokens, amounts);
  }

  function _beforeSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    bytes calldata hookData
  ) internal view override returns (bytes4, BeforeSwapDelta, uint24) {
    require(whitelisted[sender], KSHookNotWhitelisted(sender));
    require(params.amountSpecified < 0, KSHookExactOutputDisabled());

    (
      int256 minAmountIn,
      int256 maxAmountIn,
      int256 maxExchangeRate,
      uint32 log2ExchangeRateDenom,
      uint64 expiryTime,
      address operator,
      bytes memory signature
    ) = abi.decode(hookData, (int256, int256, int256, uint32, uint64, address, bytes));

    require(block.timestamp <= expiryTime, KSHookExpiredSignature());
    require(operators[operator], KyberSwapRole.KSRoleNotOperator(operator));
    require(
      minAmountIn <= -params.amountSpecified && -params.amountSpecified <= maxAmountIn,
      KSHookInvalidAmountIn(minAmountIn, maxAmountIn, -params.amountSpecified)
    );
    require(
      SignatureChecker.isValidSignatureNow(
        operator,
        keccak256(
          abi.encode(
            key,
            params.zeroForOne,
            minAmountIn,
            maxAmountIn,
            maxExchangeRate,
            log2ExchangeRateDenom,
            expiryTime
          )
        ),
        signature
      ),
      KSHookInvalidSignature()
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
    (,, int256 maxExchangeRate, uint32 log2ExchangeRateDenom,,,) =
      abi.decode(hookData, (int256, int256, int256, uint32, uint64, address, bytes));

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

      int256 maxAmountOut = (amountIn * maxExchangeRate) >> log2ExchangeRateDenom;
      int256 surplusAmount = maxAmountOut < amountOut ? amountOut - maxAmountOut : int256(0);
      if (surplusAmount > 0) {
        poolManager.mint(
          address(this), uint256(uint160(Currency.unwrap(currencyOut))), uint256(surplusAmount)
        );

        emit KSHookSeizeSurplusToken(Currency.unwrap(currencyOut), surplusAmount);
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
}
