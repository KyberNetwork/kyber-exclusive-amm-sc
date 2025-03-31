// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.s.sol';

/// @notice Mines the address and deploys the UniswapV4KEMHook.sol Hook contract
contract DeployScript is BaseUniswapScript {
  function run() public {
    // Deploy the hook using CREATE3
    // Follow the instructions in
    // https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/?tab=readme-ov-file#deploy
    // to find the suitable salt
    bytes32 salt = 0x445a84c05d0edc98679a0dc3f9ecc0c33eab94f5b5448daa9b4e400000ca69ca;
    bytes memory bytecode = abi.encodePacked(
      type(UniswapV4KEMHook).creationCode,
      abi.encode(poolManager, admin, quoteSigner, egRecipient)
    );

    vm.broadcast();
    address deployedHook = _deployContract(salt, bytecode);
    _writeAddress('uniswap-v4-kem-hook', deployedHook);

    emit DeployContract('uniswap-v4-kem-hook', deployedHook);
  }
}
