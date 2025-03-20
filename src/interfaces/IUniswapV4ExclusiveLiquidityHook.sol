// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/contracts/interfaces/IERC20.sol';
import 'uniswap/v4-core/interfaces/IHooks.sol';
import 'uniswap/v4-core/types/Currency.sol';

interface IUniswapV4ExclusiveLiquidityHook is IHooks {
  event UpdateRouter(address router, bool grantOrRevoke);

  error KSHookNotRouter(address router);

  error InvalidSurplusRecipient();

  /**
   * @notice Claim surplus tokens accrued by the hook
   * @param ids the addresses of the tokens to claim, padded with 0s: `uint256(uint160(token))`
   */
  function claimSurplusTokens(uint256[] calldata ids) external;
}
