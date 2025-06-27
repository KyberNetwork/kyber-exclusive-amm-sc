// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IKEMHookV2State
 * @notice Common state getters for the KEMHookV2 contracts
 */
interface IKEMHookV2State {
  struct TickEGInfo {
    uint256 egGrowthOutside0X128;
    uint256 egGrowthOutside1X128;
  }

  struct PoolEGState {
    uint24 protocolEGFee;
    uint256 egGrowthGlobal0X128;
    uint256 egGrowthGlobal1X128;
    mapping(int24 tick => TickEGInfo) ticks;
  }

  struct PositionEGInfo {
    uint128 liquidity;
    uint256 egGrowthInside0LastX128;
    uint256 egGrowthInside1LastX128;
  }

  /// @notice Returns the role for the claimants
  function CLAIM_ROLE() external view returns (bytes32);

  /// @notice Returns the address responsible for signing the quote
  function quoteSigner() external view returns (address);

  /// @notice Returns the address of the equilibrium-gain recipient
  function egRecipient() external view returns (address);

  /// @notice Returns the unclaimed protocol EG amount of a given token
  function protocolEGUnclaimed(address token) external view returns (uint256);

  /// @notice Returns the liquidity and last EG growth inside the position
  function positionEGInfos(uint256 tokenId)
    external
    view
    returns (uint128 liquidity, uint256 egGrowthInside0LastX128, uint256 egGrowthInside1LastX128);

  /// @notice Returns the protocol EG fee of a given pool, denominated in hundredths of a bip
  function getProtocolEGFee(bytes32 poolId) external view returns (uint24);

  /// @notice Returns the global EG growth of a given pool
  function getEGGrowthGlobals(bytes32 poolId)
    external
    view
    returns (uint256 egGrowthGlobal0X128, uint256 egGrowthGlobal1X128);

  /// @notice Returns the EG growth outside a tick for a given pool and tick
  function getTickEGGrowthOutside(bytes32 poolId, int24 tick)
    external
    view
    returns (uint256 egGrowthOutside0X128, uint256 egGrowthOutside1X128);
}
