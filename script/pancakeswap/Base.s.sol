// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// import '../Base.s.sol';

// import 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol';
// import 'pancakeswap/infinity-core/src/pool-cl/libraries/TickMath.sol';
// import 'pancakeswap/infinity-core/src/types/Currency.sol';
// import 'pancakeswap/infinity-core/test/pool-cl/helpers/LiquidityAmounts.sol';

// import 'pancakeswap/infinity-periphery/src/libraries/Actions.sol';
// import 'pancakeswap/infinity-periphery/src/pool-cl/interfaces/ICLPositionManager.sol';

// import 'src/PancakeSwapInfinityKEMHook.sol';

// contract BasePancakeSwapScript is BaseScript {
//   ICLPoolManager poolManager;
//   ICLPositionManager positionManager;
//   IHooks hook;

//   function setUp() public override {
//     super.setUp();

//     poolManager = ICLPoolManager(_readAddress('pancakeswap-infinity-cl-pool-manager'));
//     positionManager = ICLPositionManager(_readAddress('pancakeswap-infinity-cl-position-manager'));
//     hook = IHooks(_readAddressOr('pancakeswap-infinity-kem-hook', address(0)));
//   }
// }
