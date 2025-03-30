// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.s.sol';

import {Hooks} from 'pancakeswap/infinity-core/src/libraries/Hooks.sol';
import {ICLPoolManager} from 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol';

import 'src/pancakeswap/PancakeswapInfinityELHook.sol';

/// @notice Deploys the PancakeswapInfinityELHook.sol Hook contract
contract DeployScript is BaseScript {
  function run() public {
    ICLPoolManager poolManager = ICLPoolManager(_readAddress('pancakeswap-infinity-pool-manager'));
    address initialOwner = _readAddress('owner');
    address[] memory initialOperators = _readAddressArray('operators');
    address initialQuoteSigner = _readAddress('quote-signer');
    address initialSurplusRecipient = _readAddress('surplus-recipient');

    // Deploy the hook using CREATE3
    bytes32 salt = keccak256('KS');
    bytes memory bytecode = abi.encodePacked(
      type(PancakeswapInfinityELHook).creationCode,
      abi.encode(
        poolManager, initialOwner, initialOperators, initialQuoteSigner, initialSurplusRecipient
      )
    );

    vm.broadcast();
    address hook = _deployContract(salt, bytecode);
    _writeAddress('pancakeswap-infinity-el-hook', hook);

    emit DeployContract('pancakeswap-infinity-el-hook', hook);
  }
}
