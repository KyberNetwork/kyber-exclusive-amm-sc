// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import '../UniswapV4FFHook.sol';

contract UniswapV4FFHookHarness is UniswapV4FFHook {
  constructor(
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address[] memory initialRescuers,
    IPoolManager _poolManager
  )
    UniswapV4FFHook(
      initialAdmin,
      initialQuoteSigner,
      initialEgRecipient,
      initialOperators,
      initialGuardians,
      initialRescuers,
      _poolManager
    )
  {}

  function updateProtocolEGUnclaimed(address token, uint256 amount) external {
    protocolEGUnclaimed[token] = amount;
  }
}
