// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../interfaces/IKEMHookV2.sol';

import {HookDataDecoderV2} from '../libraries/HookDataDecoderV2.sol';
import {UnorderedNonce} from './UnorderedNonce.sol';

import {Management} from 'ks-common-sc/src/base/Management.sol';
import {Rescuable} from 'ks-common-sc/src/base/Rescuable.sol';

import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

abstract contract BaseKEMHookV2 is IKEMHookV2, Rescuable, Management, UnorderedNonce {
  /// @inheritdoc IKEMHookV2State
  bytes32 public constant CLAIM_ROLE = keccak256('CLAIM_ROLE');

  int256 constant MAX_UINT128 = (1 << 128) - 1;

  /// @inheritdoc IKEMHookV2State
  address public quoteSigner;

  /// @inheritdoc IKEMHookV2State
  address public egRecipient;

  /// @inheritdoc IKEMHookV2State
  mapping(bytes32 => int256) public protocolEGFeeOf;

  /// @inheritdoc IKEMHookV2State
  mapping(address => uint256) public protocolEGAmountOf;

  constructor(
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialClaimants
  ) Management(initialAdmin) {
    quoteSigner = initialQuoteSigner;
    egRecipient = initialEgRecipient;

    for (uint256 i = 0; i < initialClaimants.length; i++) {
      _grantRole(CLAIM_ROLE, initialClaimants[i]);
    }
  }

  /// @inheritdoc IKEMHookV2Admin
  function updateQuoteSigner(address newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
    address oldSigner = quoteSigner;
    quoteSigner = newSigner;

    emit UpdateQuoteSigner(oldSigner, newSigner);
  }

  /// @inheritdoc IKEMHookV2Admin
  function updateEGRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
    address oldRecipient = egRecipient;
    egRecipient = newRecipient;

    emit UpdateEGRecipient(oldRecipient, newRecipient);
  }

  /// @inheritdoc IKEMHookV2Admin
  function updateProtocolEGFee(bytes32 poolId, int256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
    int256 oldFee = protocolEGFeeOf[poolId];
    protocolEGFeeOf[poolId] = newFee;

    emit UpdateProtocolEGFee(poolId, oldFee, newFee);
  }

  function _handleCallback(bytes calldata data) internal {
    ClaimType claimType = ClaimType(uint8(data[0]));
    if (claimType == ClaimType.ProtocolEG) {
      _claimProtocolEG(data[1:]);
    } else if (claimType == ClaimType.PositionEG) {
      _claimPositionEG(data[1:]);
    }
  }

  function _claimProtocolEG(bytes calldata data) internal {
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
        _take(token, _egRecipient, amount);
      }
    }

    emit ClaimProtocolEG(_egRecipient, tokens, amounts);
  }

  function _take(address token, address recipient, uint256 amount) internal virtual;

  function _claimPositionEG(bytes calldata data) internal virtual;

  function _beforeSwap(
    address sender,
    bytes32 poolId,
    bool zeroForOne,
    int256 amountSpecified,
    bytes calldata hookData
  ) internal {
    require(amountSpecified < 0, ExactOutputDisabled());

    (
      int256 maxAmountIn,
      int256 maxExchangeRate,
      uint256 nonce,
      uint256 expiryTime,
      bytes memory signature
    ) = HookDataDecoderV2.decodeAllHookData(hookData);

    require(block.timestamp <= expiryTime, ExpiredSignature(expiryTime, block.timestamp));
    unchecked {
      require(-amountSpecified <= maxAmountIn, ExceededMaxAmountIn(maxAmountIn, -amountSpecified));
    }

    _useUnorderedNonce(nonce);

    bytes32 hash = keccak256(
      abi.encode(sender, poolId, zeroForOne, maxAmountIn, maxExchangeRate, nonce, expiryTime)
    );
    require(SignatureChecker.isValidSignatureNow(quoteSigner, hash, signature), InvalidSignature());
  }

  function _afterSwap(
    bytes32 poolId,
    address tokenOut,
    bool zeroForOne,
    int256 delta,
    bytes calldata hookData
  ) internal returns (int256 totalEGAmount) {
    int256 amountIn;
    int256 amountOut;
    unchecked {
      if (zeroForOne) {
        (amountIn, amountOut) = _unpack(delta);
      } else {
        (amountOut, amountIn) = _unpack(delta);
      }
      amountIn = -amountIn;
    }

    int256 maxExchangeRate = HookDataDecoderV2.decodeMaxExchangeRate(hookData);
    int256 maxAmountOut = amountIn * maxExchangeRate / MAX_UINT128;

    unchecked {
      totalEGAmount = maxAmountOut < amountOut ? amountOut - maxAmountOut : int256(0);
      if (totalEGAmount > 0) {
        int256 protocolEGAmount = totalEGAmount * protocolEGFeeOf[poolId] / MAX_UINT128;
        if (protocolEGAmount > 0) {
          protocolEGAmountOf[tokenOut] += uint256(protocolEGAmount);
        }
      }
    }
  }

  function _unpack(int256 delta) internal pure returns (int256 amount0, int256 amount1) {
    assembly {
      amount0 := sar(128, delta)
      amount1 := signextend(15, delta)
    }
  }
}
