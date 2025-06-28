// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title FFHookStateView
/// @notice State view module for the FFHook contract
abstract contract FFHookStateView {
  /// @notice The slot of the slot0 data before the swap
  bytes32 internal constant SLOT0_DATA_BEFORE_SLOT = keccak256('slot0DataBefore.slot');

  /// @notice The slot of the liquidity before the swap
  bytes32 internal constant LIQUIDITY_BEFORE_SLOT = keccak256('liquidityBefore.slot');

  /// @notice Retrieves the packed slot0 data of a pool
  function _getSlot0Data(bytes32 poolId) internal view virtual returns (bytes32 slot0Data);

  /// @notice Retrieves the liquidity of a pool
  function _getLiquidity(bytes32 poolId) internal view virtual returns (uint128 liquidity);

  /// @notice Retrieves the tick bitmap of a pool at a specific word
  function _getTickBitmap(bytes32 poolId, int16 word)
    internal
    view
    virtual
    returns (uint256 tickBitmap);

  /// @notice Retrieves the liquidity gross and net of a pool at a specific tick
  function _getTickLiquidity(bytes32 poolId, int24 tick)
    internal
    view
    virtual
    returns (uint128 liquidityGross, int128 liquidityNet);

  /// @notice Retrieves the liquidity of a position
  function _getPositionLiquidity(
    bytes32 poolId,
    address owner,
    int24 tickLower,
    int24 tickUpper,
    bytes32 salt
  ) internal view virtual returns (uint128 liquidity);
}
