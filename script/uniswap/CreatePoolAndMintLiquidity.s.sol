// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './Base.s.sol';

contract CreatePoolAndMintLiquidityScript is BaseUniswapScript {
  using CurrencyLibrary for Currency;
  using SafeERC20 for IERC20;

  /////////////////////////////////////
  // --- Parameters to Configure --- //
  /////////////////////////////////////

  CreatePoolAndAddLiquidityRawParams rawParams = CreatePoolAndAddLiquidityRawParams({
    token0: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
    token1: address(0),
    lpFee: 3e3, // 0.3%
    tickSpacing: 10,
    initPrice: 0.0005e18, // price of token0 / token1, base 1e18
    priceTickLower: 0.0004e18,
    priceTickUpper: 0.0006e18,
    token0Amount: 1000e6, // accounting decimal precision
    token1Amount: 1e18 // accounting decimal precision
  });

  address msgSender = 0x4f82e73EDb06d29Ff62C91EC8f5Ff06571bdeb29;

  /////////////////////////////////////

  function run() external {
    require(rawParams.token0 != address(0) || rawParams.token1 != address(0), 'Invalid tokens');
    require(
      rawParams.lpFee > 0 && rawParams.tickSpacing > 0 && rawParams.initPrice > 0,
      'Invalid pool parameters'
    );
    require(rawParams.token0Amount > 0 && rawParams.token1Amount > 0, 'Invalid token amounts');
    require(rawParams.priceTickLower < rawParams.priceTickUpper, 'Invalid position range');
    require(msgSender != address(0), 'Invalid msgSender');

    CreatePoolAndAddLiquidityParsedParams memory parsedParams = _parsePoolConfig(rawParams);

    Currency currency0 = Currency.wrap(address(parsedParams.token0));
    Currency currency1 = Currency.wrap(address(parsedParams.token1));

    uint24 lpFee = parsedParams.lpFee;
    int24 tickSpacing = parsedParams.tickSpacing;
    uint160 startingPrice = parsedParams.initSqrtPriceX96;
    int24 tickLower = parsedParams.tickLower;
    int24 tickUpper = parsedParams.tickUpper;
    uint256 token0Amount = parsedParams.token0Amount;
    uint256 token1Amount = parsedParams.token1Amount;

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
    tokenApprovals(currency0, currency1);
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

  function tokenApprovals(Currency currency0, Currency currency1) public {
    if (!currency0.isAddressZero()) {
      IERC20 token0 = IERC20(Currency.unwrap(currency0));
      _safeApproveAllowancePermit2(permit2, token0, address(positionManager));
    }
    if (!currency1.isAddressZero()) {
      IERC20 token1 = IERC20(Currency.unwrap(currency1));
      _safeApproveAllowancePermit2(permit2, token1, address(positionManager));
    }
  }

  function _safeApproveAllowancePermit2(IAllowanceTransfer permit2, IERC20 token, address spender)
    internal
  {
    (uint160 currentAllowance,,) = permit2.allowance(address(this), address(token), spender);
    if (currentAllowance == 0) {
      token.forceApprove(address(permit2), type(uint256).max);
      permit2.approve(address(token), spender, type(uint160).max, type(uint48).max);
    }
  }
}
