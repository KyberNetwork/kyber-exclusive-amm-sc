// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKEMHookV2State} from '../interfaces/IKEMHookV2State.sol';

abstract contract BaseKEMHookV2State is IKEMHookV2State {
  /// @inheritdoc IKEMHookV2State
  bytes32 public constant CLAIM_ROLE = keccak256('CLAIM_ROLE');

  uint256 internal constant PIPS_DENOMINATOR = 1_000_000;

  uint256 internal constant EXCHANGE_RATE_DENOMINATOR = type(uint128).max;

  /// @inheritdoc IKEMHookV2State
  address public quoteSigner;

  /// @inheritdoc IKEMHookV2State
  address public egRecipient;

  /// @inheritdoc IKEMHookV2State
  mapping(address => uint256) public protocolEGUnclaimed;

  /// @inheritdoc IKEMHookV2State
  mapping(uint256 tokenId => PositionEGInfo) public positionEGInfos;

  /// @notice The EG state for each pool
  mapping(bytes32 poolId => PoolEGState) internal pools;

  /// @inheritdoc IKEMHookV2State
  function getProtocolEGFee(bytes32 poolId) external view returns (uint24) {
    return pools[poolId].protocolEGFee;
  }

  /// @inheritdoc IKEMHookV2State
  function getEGGrowthGlobals(bytes32 poolId)
    external
    view
    returns (uint256 egGrowthGlobal0X128, uint256 egGrowthGlobal1X128)
  {
    return (pools[poolId].egGrowthGlobal0X128, pools[poolId].egGrowthGlobal1X128);
  }

  /// @inheritdoc IKEMHookV2State
  function getTickEGGrowthOutside(bytes32 poolId, int24 tick)
    external
    view
    returns (uint256 egGrowthOutside0X128, uint256 egGrowthOutside1X128)
  {
    TickEGInfo storage tickEGInfo = pools[poolId].ticks[tick];
    return (tickEGInfo.egGrowthOutside0X128, tickEGInfo.egGrowthOutside1X128);
  }
}
