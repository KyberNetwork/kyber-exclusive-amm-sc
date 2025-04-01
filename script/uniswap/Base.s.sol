// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.s.sol';

import 'uniswap/v4-core/src/interfaces/IPoolManager.sol';
import 'uniswap/v4-core/src/libraries/TickMath.sol';
import 'uniswap/v4-core/src/types/Currency.sol';
import 'uniswap/v4-core/test/utils/LiquidityAmounts.sol';

import 'uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import 'uniswap/v4-periphery/src/libraries/Actions.sol';

import 'permit2/src/interfaces/IAllowanceTransfer.sol';

import 'src/UniswapV4KEMHook.sol';

contract BaseUniswapScript is BaseScript {
  using Address for address;

  IPoolManager poolManager;
  IPositionManager positionManager;
  IHooks hook;
  IAllowanceTransfer permit2;

  function setUp() public override {
    super.setUp();

    poolManager = IPoolManager(_readAddress('uniswap-v4-pool-manager'));
    positionManager = IPositionManager(_readAddress('uniswap-v4-position-manager'));
    hook = IHooks(_readAddressOr('uniswap-v4-kem-hook', address(0)));
    permit2 = abi.decode(
      address(positionManager).functionStaticCall(abi.encodeWithSignature('permit2()')),
      (IAllowanceTransfer)
    );
  }
}
