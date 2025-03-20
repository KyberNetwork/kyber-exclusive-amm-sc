// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './interfaces/IUniswapV4ExclusiveLiquidityHook.sol';

import 'uniswap/v4-core/types/Currency.sol';
import 'uniswap/v4-periphery/utils/BaseHook.sol';

import {KSRescueV2, Ownable} from 'ks-growth-utils-sc/KSRescueV2.sol';

contract UniswapV4ExclusiveLiquidityHook is IUniswapV4ExclusiveLiquidityHook, BaseHook, KSRescueV2 {
  mapping(address => bool) public routers;

  address surplusRecipient;

  constructor(
    IPoolManager _poolManager,
    address initialOwner,
    address[] memory initialOperators,
    address[] memory initialGuardians
  ) BaseHook(_poolManager) Ownable(initialOwner) {
    for (uint256 i = 0; i < initialOperators.length; i++) {
      operators[initialOperators[i]] = true;

      emit UpdateOperator(initialOperators[i], true);
    }
    for (uint256 i = 0; i < initialGuardians.length; i++) {
      guardians[initialGuardians[i]] = true;

      emit UpdateGuardian(initialGuardians[i], true);
    }
  }

  function updateRouter(address router, bool grantOrRevoke) external onlyOwner {
    routers[router] = grantOrRevoke;

    emit UpdateRouter(router, grantOrRevoke);
  }

  function updateSurplusRecipient(address recipient) external onlyOwner {
    require(recipient != address(0), InvalidSurplusRecipient());
    surplusRecipient = recipient;
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

  function claimSurplusTokens(uint256[] calldata ids) public onlyOperator {
    poolManager.unlock(abi.encode(ids));
  }

  function unlockCallback(bytes calldata data) external returns (bytes memory) {
    uint256[] memory ids = abi.decode(data, (uint256[]));

    for (uint256 i = 0; i < ids.length; i++) {
      uint256 id = ids[i];
      uint256 balance = poolManager.balanceOf(address(this), id);
      if (balance > 0) {
        poolManager.burn(address(this), id, balance);
        poolManager.take(Currency.wrap(address(uint160(id))), surplusRecipient, balance);
      }
    }
  }
}
