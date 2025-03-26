// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.s.sol';

import {IPoolManager} from 'uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {Hooks} from 'uniswap/v4-core/src/libraries/Hooks.sol';
import {HookMiner} from 'uniswap/v4-periphery/src/utils/HookMiner.sol';

import 'src/UniswapV4ELHook.sol';

/// @notice Mines the address and deploys the Counter.sol Hook contract
contract DeployUniswapV4ELHookScript is BaseScript {
  address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

  function setUp() public {}

  function run() public {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }

    IPoolManager poolManager =
      IPoolManager(_readAddress('script/configs/pool-manager.json', chainId));
    address initialOwner = _readAddress('script/configs/owner.json', chainId);
    address[] memory initialOperators = _readAddressArray('script/configs/operators.json', chainId);
    address initialSigner = _readAddress('script/configs/signer.json', chainId);
    address initialSurplusRecipient = _readAddress('script/configs/surplus-recipient.json', chainId);

    console.log('poolManager:', address(poolManager));
    console.log('initialOwner:', initialOwner);
    console.log('initialOperators:', initialOperators[0]);
    console.log('initialSurplusRecipient:', initialSurplusRecipient);

    // hook contracts must have specific flags encoded in the address
    uint160 flags =
      uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);

    bytes memory constructorArgs = abi.encode(
      poolManager, initialOwner, initialOperators, initialSigner, initialSurplusRecipient
    );

    // Mine a salt that will produce a hook address with the correct flags
    (address hookAddress, bytes32 salt) =
      HookMiner.find(CREATE2_DEPLOYER, flags, type(UniswapV4ELHook).creationCode, constructorArgs);

    // Deploy the hook using CREATE2
    vm.broadcast();
    UniswapV4ELHook counter = new UniswapV4ELHook{salt: salt}(
      IPoolManager(poolManager),
      initialOwner,
      initialOperators,
      initialSigner,
      initialSurplusRecipient
    );
    require(address(counter) == hookAddress, 'CounterScript: hook address mismatch');
  }
}
