// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.s.sol';

/// @notice Deploys the PancakeswapInfinityKEMHook.sol Hook contract
contract DeployScript is BasePancakeswapScript {
  function run() public {
    // Deploy the hook using CREATE3
    bytes32 salt = keccak256('KS');
    bytes memory bytecode = abi.encodePacked(
      type(PancakeswapInfinityKEMHook).creationCode,
      abi.encode(poolManager, owner, operators, quoteSigner, surplusRecipient)
    );

    vm.broadcast();
    address deployedHook = _deployContract(salt, bytecode);
    _writeAddress('pancakeswap-infinity-kem-hook', deployedHook);

    emit DeployContract('pancakeswap-infinity-kem-hook', deployedHook);
  }
}
