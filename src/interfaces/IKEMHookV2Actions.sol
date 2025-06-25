// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IKEMHookActions
 * @notice Common actions for the KEMHookV2 contracts
 */
interface IKEMHookV2Actions {
  /**
   * @notice Claim a position's shares of EG on a pool
   * @notice Can only be called by the owner of the position
   * @param tokenId the token id
   */
  function claimPositionEG(uint256 tokenId) external;
}
