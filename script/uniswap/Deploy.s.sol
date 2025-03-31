// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.s.sol';

/// @notice Mines the address and deploys the UniswapV4ELHook.sol Hook contract
contract DeployScript is BaseUniswapScript {
  function run() public {
    // Deploy the hook using CREATE3
    // Follow the instructions in
    // https://github.com/KyberNetwork/ks-exclusive-liquidity-sc/?tab=readme-ov-file#deploy
    // to find the suitable salt
    bytes32 salt = 0x000000000000000000000000000000000000000034b3d923ecc20000000007e1;
    bytes memory bytecode = abi.encodePacked(
      type(UniswapV4ELHook).creationCode,
      abi.encode(poolManager, owner, operators, quoteSigner, surplusRecipient)
    );

    vm.broadcast();
    address deployedHook = _deployContract(salt, bytecode);
    _writeAddress('uniswap-v4-el-hook', deployedHook);

    emit DeployContract('uniswap-v4-el-hook', deployedHook);
  }
}
