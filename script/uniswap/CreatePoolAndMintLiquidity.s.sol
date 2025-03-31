// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.s.sol';

contract CreatePoolAndMintLiquidityScript is BaseUniswapScript {
  using CurrencyLibrary for Currency;

  /////////////////////////////////////
  // --- Parameters to Configure --- //
  /////////////////////////////////////

  // --- pool configuration --- //
  IERC20 token0;
  IERC20 token1;
  Currency currency0 = Currency.wrap(address(token0));
  Currency currency1 = Currency.wrap(address(token1));

  // fees paid by swappers that accrue to liquidity providers
  uint24 lpFee;
  int24 tickSpacing;

  // starting price of the pool, in sqrtPriceX96
  uint160 startingPrice;

  // --- liquidity position configuration --- //
  uint256 public token0Amount;
  uint256 public token1Amount;

  // range of the position
  int24 tickLower; // must be a multiple of tickSpacing
  int24 tickUpper;
  /////////////////////////////////////

  address msgSender;

  function run() external {
    require(
      token0 != IERC20(address(0)) && token1 != IERC20(address(0)) && token0 < token1,
      'Invalid tokens'
    );
    require(lpFee > 0 && tickSpacing > 0 && startingPrice > 0, 'Invalid pool parameters');
    require(token0Amount > 0 && token1Amount > 0, 'Invalid token amounts');
    require(
      tickLower < tickUpper && tickLower % tickSpacing == 0 && tickUpper % tickSpacing == 0,
      'Invalid tick range'
    );
    require(msgSender != address(0), 'Invalid msgSender');

    // tokens should be sorted
    PoolKey memory pool = PoolKey({
      currency0: currency0,
      currency1: currency1,
      fee: lpFee,
      tickSpacing: tickSpacing,
      hooks: hook
    });
    bytes memory hookData = new bytes(0);

    // --------------------------------- //

    // Converts token amounts to liquidity units
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      startingPrice,
      TickMath.getSqrtPriceAtTick(tickLower),
      TickMath.getSqrtPriceAtTick(tickUpper),
      token0Amount,
      token1Amount
    );

    // slippage limits
    uint256 amount0Max = token0Amount + 1 wei;
    uint256 amount1Max = token1Amount + 1 wei;

    (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
      pool, tickLower, tickUpper, liquidity, amount0Max, amount1Max, address(this), hookData
    );

    // multicall parameters
    bytes[] memory params = new bytes[](2);

    // initialize pool
    params[0] =
      abi.encodeWithSelector(positionManager.initializePool.selector, pool, startingPrice, hookData);

    // mint liquidity
    params[1] = abi.encodeWithSelector(
      positionManager.modifyLiquidities.selector,
      abi.encode(actions, mintParams),
      block.timestamp + 60
    );

    // if the pool is an ETH pair, native tokens are to be transferred
    uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;

    vm.startBroadcast();
    tokenApprovals();
    vm.stopBroadcast();

    // multicall to atomically create pool & add liquidity
    vm.broadcast();
    positionManager.multicall{value: valueToPass}(params);
  }

  /// @dev helper function for encoding mint liquidity operation
  /// @dev does NOT encode SWEEP, developers should take care when minting liquidity on an ETH pair
  function _mintLiquidityParams(
    PoolKey memory poolKey,
    int24 _tickLower,
    int24 _tickUpper,
    uint256 liquidity,
    uint256 amount0Max,
    uint256 amount1Max,
    address recipient,
    bytes memory hookData
  ) internal view returns (bytes memory, bytes[] memory) {
    bytes memory actions = abi.encodePacked(
      uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP)
    );

    bytes[] memory params = new bytes[](3);
    params[0] = abi.encode(
      poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData
    );
    params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
    params[2] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, msgSender);
    return (actions, params);
  }

  function tokenApprovals() public {
    if (!currency0.isAddressZero()) {
      token0.approve(address(permit2), type(uint256).max);
      permit2.approve(
        address(token0), address(positionManager), type(uint160).max, type(uint48).max
      );
    }
    if (!currency1.isAddressZero()) {
      token1.approve(address(permit2), type(uint256).max);
      permit2.approve(
        address(token1), address(positionManager), type(uint160).max, type(uint48).max
      );
    }
  }
}
