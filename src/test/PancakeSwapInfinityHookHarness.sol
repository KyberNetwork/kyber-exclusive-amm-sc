// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import '../PancakeSwapInfinityFFHook.sol';

contract PancakeSwapInfinityFFHookHarness is PancakeSwapInfinityFFHook {
  constructor(
    address initialAdmin,
    address initialQuoteSigner,
    address initialEgRecipient,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address[] memory initialRescuers,
    ICLPoolManager _poolManager
  )
    PancakeSwapInfinityFFHook(
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
