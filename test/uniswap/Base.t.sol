// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../Base.t.sol';
import 'src/BaseKEMHook.sol';
import 'src/uniswap/UniswapV4KEMHook.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import 'uniswap/v4-core/src/libraries/CustomRevert.sol';
import 'uniswap/v4-core/test/utils/Deployers.sol';

contract UniswapHookBaseTest is BaseTest, Deployers {
  address hook;
  PoolKey keyWithoutHook;
  PoolKey keyWithHook;

  PoolSwapTest.TestSettings testSettings =
    PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

  function setUp() public override {
    super.setUp();

    initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    keyWithoutHook = key;

    hook = address(
      uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)
    );
    deployCodeTo(
      'UniswapV4KEMHook.sol',
      abi.encode(manager, owner, newAddressesLength1(operator), quoteSigner, egRecipient),
      hook
    );

    (keyWithHook,) =
      initPoolAndAddLiquidity(currency0, currency1, IHooks(hook), 3000, SQRT_PRICE_1_1);

    vm.prank(owner);
    IKEMHook(hook).whitelistSenders(newAddressesLength1(address(swapRouter)), true);
  }

  function getMinPriceLimit() internal pure override returns (uint160) {
    return MIN_PRICE_LIMIT;
  }

  function getMaxPriceLimit() internal pure override returns (uint160) {
    return MAX_PRICE_LIMIT;
  }

  function getSqrtPrice1_1() internal pure override returns (uint160) {
    return SQRT_PRICE_1_1;
  }
}
