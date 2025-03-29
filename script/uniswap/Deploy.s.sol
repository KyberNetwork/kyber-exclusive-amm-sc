// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.s.sol';

import {IPoolManager} from 'uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {Hooks} from 'uniswap/v4-core/src/libraries/Hooks.sol';

import 'src/uniswap/UniswapV4ELHook.sol';

/// @notice Mines the address and deploys the UniswapV4ELHook.sol Hook contract
contract DeployScript is BaseScript {
  address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

  function run() public {
    IPoolManager poolManager = IPoolManager(_readAddress('uniswap-v4-pool-manager'));
    address initialOwner = _readAddress('owner');
    address[] memory initialOperators = _readAddressArray('operators');
    address initialQuoteSigner = _readAddress('quote-signer');
    address initialSurplusRecipient = _readAddress('surplus-recipient');

    // hook contracts must have specific flags encoded in the address
    uint160 flags =
      uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);

    // Deploy the hook using CREATE3
    bytes32 salt = 0x000000000000000000000000000000000000000016bc76e7e513700000000b0a;
    bytes memory bytecode = abi.encodePacked(
      type(UniswapV4ELHook).creationCode,
      abi.encode(
        poolManager, initialOwner, initialOperators, initialQuoteSigner, initialSurplusRecipient
      )
    );

    // Deploy the hook using CREATE3
    vm.broadcast();
    address hook = _deployContract(salt, bytecode);
    _writeAddress('uniswap-v4-el-hook', hook);

    emit DeployContract('uniswap-v4-el-hook', hook);
  }
}
