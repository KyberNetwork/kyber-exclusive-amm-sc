// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.t.sol';
import 'src/BaseKEMHook.sol';
import 'src/pancakeswap/PancakeSwapInfinityKEMHook.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import 'pancakeswap/infinity-core/src/libraries/CustomRevert.sol';
import 'pancakeswap/infinity-core/src/pool-cl/interfaces/ICLHooks.sol';
import 'pancakeswap/infinity-core/src/pool-cl/libraries/CLPoolParametersHelper.sol';
import 'pancakeswap/infinity-core/test/helpers/TokenFixture.sol';
import {CLPoolManagerRouter} from
  'pancakeswap/infinity-core/test/pool-cl/helpers/CLPoolManagerRouter.sol';
import 'pancakeswap/infinity-core/test/pool-cl/helpers/Deployers.sol';

contract PancakeSwapHookBaseTest is BaseTest, Deployers, TokenFixture {
  using CLPoolParametersHelper for bytes32;

  IVault public vault;
  CLPoolManager public poolManager;
  CLPoolManagerRouter public swapRouter;
  PoolKey keyWithoutHook;
  PoolKey keyWithHook;

  CLPoolManagerRouter.SwapTestSettings testSettings =
    CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

  function setUp() public override {
    super.setUp();

    initializeTokens();
    (vault, poolManager) = createFreshManager();
    swapRouter = new CLPoolManagerRouter(vault, poolManager);
    hook = IKEMHook(new PancakeSwapInfinityKEMHook(poolManager, admin, quoteSigner, egRecipient));

    MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
    MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
    token0.mint(address(this), 2 ** 255);
    token1.mint(address(this), 2 ** 255);
    token0.approve(address(swapRouter), 1000 ether);
    token1.approve(address(swapRouter), 1000 ether);
    token0.approve(address(hook), 1000 ether);
    token1.approve(address(hook), 1000 ether);

    keyWithoutHook = PoolKey({
      currency0: currency0,
      currency1: currency1,
      hooks: IHooks(address(0)),
      poolManager: poolManager,
      fee: uint24(3000),
      parameters: bytes32(uint256(0xa0000))
    });
    keyWithHook = PoolKey({
      currency0: currency0,
      currency1: currency1,
      hooks: IHooks(address(hook)),
      poolManager: poolManager,
      fee: uint24(3000),
      parameters: bytes32(uint256(IHooks(address(hook)).getHooksRegistrationBitmap())).setTickSpacing(
        10
      )
    });

    poolManager.initialize(keyWithoutHook, getSqrtPrice1_1());
    poolManager.initialize(keyWithHook, getSqrtPrice1_1());

    vm.startPrank(admin);
    hook.grantRole(CLAIM_ROLE, operator);
    hook.grantRole(SWAP_ROLE, address(swapRouter));
    vm.stopPrank();
  }

  function getMinPriceLimit() internal pure override returns (uint160) {
    return MIN_PRICE_LIMIT;
  }

  function getMaxPriceLimit() internal pure override returns (uint160) {
    return MAX_PRICE_LIMIT;
  }

  function getSqrtPrice1_1() internal pure override returns (uint160) {
    return SQRT_RATIO_1_1;
  }
}
