// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './interfaces/IUniswapV4ExclusiveLiquidityHook.sol';

import 'openzeppelin-contracts/contracts/access/Ownable.sol';
import 'uniswap/v4-periphery/utils/BaseHook.sol';

contract UniswapV4ExclusiveLiquidityHook is IUniswapV4ExclusiveLiquidityHook, BaseHook, Ownable {
  mapping(address => bool) public whitelistedOperators;

  mapping(address => bool) public whitelistedRouters;

  constructor(IPoolManager _poolManager, address initialOwner)
    BaseHook(_poolManager)
    Ownable(initialOwner)
  {}

  modifier onlyWhitelistedOperator() {
    require(whitelistedOperators[msg.sender], NotWhitelistedOperator(msg.sender));
    _;
  }

  function whitelistOperators(address[] calldata operators, bool status) external onlyOwner {
    for (uint256 i = 0; i < operators.length; i++) {
      whitelistedOperators[operators[i]] = status;
    }
  }

  function whitelistRouters(address[] calldata routers, bool status) external onlyOwner {
    for (uint256 i = 0; i < routers.length; i++) {
      whitelistedRouters[routers[i]] = status;
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

  function claimSurplusTokens(IERC20[] calldata tokens, address recipient)
    external
    onlyWhitelistedOperator
  {
    if (recipient == address(0)) {
      recipient = msg.sender;
    }
    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 balance = tokens[i].balanceOf(address(this));
      if (balance > 0) {
        tokens[i].transfer(recipient, balance);
      }
    }
  }
}
