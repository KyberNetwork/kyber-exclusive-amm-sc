// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.s.sol';

/// @notice Deploys the PancakeswapInfinityELHook.sol Hook contract
contract DeployScript is BasePancakeswapScript {
  function run() public {
    // Deploy the hook using CREATE3
    bytes32 salt = keccak256('KS');
    bytes memory bytecode = abi.encodePacked(
      type(PancakeswapInfinityELHook).creationCode,
      abi.encode(poolManager, owner, operators, quoteSigner, surplusRecipient)
    );

    vm.broadcast();
    address deployedHook = _deployContract(salt, bytecode);
    _writeAddress('pancakeswap-infinity-el-hook', deployedHook);

    emit DeployContract('pancakeswap-infinity-el-hook', deployedHook);
  }
}
