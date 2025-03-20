// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/contracts/interfaces/IERC20.sol';
import 'uniswap/v4-core/interfaces/IHooks.sol';

interface IUniswapV4ExclusiveLiquidityHook is IHooks {
  error NotWhitelistedOperator(address operator);

  error NotWhitelistedRouter(address router);

  function claimSurplusTokens(IERC20[] calldata tokens, address recipient) external;
}
