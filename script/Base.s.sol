// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import 'openzeppelin-contracts/contracts/utils/Address.sol';
import 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import 'uniswap/v4-core/src/libraries/FullMath.sol';
import 'uniswap/v4-core/src/libraries/TickMath.sol';

contract BaseScript is Script {
  using stdJson for string;
  using Address for address;

  event ReadAddress(string key, address result);
  event ReadBool(string key, bool result);
  event ReadAddressArray(string key, address[] result);

  event DeployContract(string key, address result);

  address constant CREATE3_DEPLOYER = 0x8Cad6A96B0a287e29bA719257d0eF431Ea6D888B;

  string path;
  string chainId;

  address owner;
  address[] claimableAccounts;
  address[] whitelistedAccounts;
  address quoteSigner;
  address egRecipient;

  struct CreatePoolAndAddLiquidityRawParams {
    address token0;
    address token1;
    uint24 lpFee;
    int24 tickSpacing;
    uint256 initPrice;
    uint256 priceTickLower;
    uint256 priceTickUpper;
    uint256 token0Amount;
    uint256 token1Amount;
  }

  struct CreatePoolAndAddLiquidityParsedParams {
    address token0;
    address token1;
    uint24 lpFee;
    int24 tickSpacing;
    uint160 initSqrtPriceX96;
    int24 tickLower;
    int24 tickUpper;
    uint256 token0Amount;
    uint256 token1Amount;
  }

  function setUp() public virtual {
    path = string.concat(vm.projectRoot(), '/script/config/');

    uint256 _chainId;
    assembly {
      _chainId := chainid()
    }
    chainId = vm.toString(_chainId);

    owner = _readAddress('owner');
    claimableAccounts = _readAddressArray('claimable-accounts');
    whitelistedAccounts = _readAddressArray('whitelisted-accounts');
    quoteSigner = _readAddress('quote-signer');
    egRecipient = _readAddress('eg-recipient');
  }

  function _getJsonString(string memory key) internal view returns (string memory) {
    try vm.readFile(string.concat(path, key, '.json')) returns (string memory json) {
      return json;
    } catch {
      return '{}';
    }
  }

  function _readAddress(string memory key) internal returns (address result) {
    string memory json = _getJsonString(key);
    result = json.readAddress(string.concat('.', chainId));

    emit ReadAddress(key, result);
  }

  function _readAddressOr(string memory key, address defaultValue)
    internal
    returns (address result)
  {
    string memory json = _getJsonString(key);
    result = json.readAddressOr(string.concat('.', chainId), defaultValue);

    emit ReadAddress(key, result);
  }

  function _writeAddress(string memory key, address value) internal {
    if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
      return;
    }
    vm.serializeJson(key, _getJsonString(key));
    vm.writeJson(key.serialize(chainId, value), string.concat(path, key, '.json'));
  }

  function _readBool(string memory key) internal returns (bool result) {
    string memory json = _getJsonString(key);
    result = json.readBool(string.concat('.', chainId));

    emit ReadBool(key, result);
  }

  function _readAddressArray(string memory key) internal returns (address[] memory result) {
    string memory json = _getJsonString(key);
    result = json.readAddressArray(string.concat('.', chainId));

    emit ReadAddressArray(key, result);
  }

  /**
   * @notice Deploy a contract using CREATE3
   * @param salt the salt to deploy the contract with
   * @param creationCode the creation code of the contract
   */
  function _deployContract(bytes32 salt, bytes memory creationCode)
    internal
    returns (address deployed)
  {
    bytes memory result = CREATE3_DEPLOYER.functionCall(
      abi.encodeWithSignature('deploy(bytes32,bytes)', salt, creationCode)
    );
    deployed = abi.decode(result, (address));
  }

  function _parsePoolConfig(CreatePoolAndAddLiquidityRawParams memory rawParams)
    internal
    view
    returns (CreatePoolAndAddLiquidityParsedParams memory parsedParams)
  {
    parsedParams.lpFee = rawParams.lpFee;
    parsedParams.tickSpacing = rawParams.tickSpacing;

    {
      uint256 initPrice;
      uint256 priceTickLower;
      uint256 priceTickUpper;

      if (rawParams.token0 < rawParams.token1) {
        (parsedParams.token0, parsedParams.token1) = (rawParams.token0, rawParams.token1);
        (parsedParams.token0Amount, parsedParams.token1Amount) =
          (rawParams.token0Amount, rawParams.token1Amount);

        initPrice = rawParams.initPrice;
        priceTickLower = rawParams.priceTickLower;
        priceTickUpper = rawParams.priceTickUpper;
      } else {
        (parsedParams.token0, parsedParams.token1) = (rawParams.token1, rawParams.token0);
        (parsedParams.token0Amount, parsedParams.token1Amount) =
          (rawParams.token1Amount, rawParams.token0Amount);

        initPrice = 1e36 / rawParams.initPrice;
        priceTickLower = 1e36 / rawParams.priceTickUpper;
        priceTickUpper = 1e36 / rawParams.priceTickLower;
      }

      uint256 decimals0 =
        parsedParams.token0 == address(0) ? 18 : IERC20Metadata(parsedParams.token0).decimals();
      uint256 decimals1 =
        parsedParams.token1 == address(0) ? 18 : IERC20Metadata(parsedParams.token1).decimals();

      uint256 initPriceX192 =
        FullMath.mulDiv(initPrice, (10 ** decimals1) << 192, 10 ** (decimals0 + 18));
      uint256 priceLowerX192 =
        FullMath.mulDiv(priceTickLower, (10 ** decimals1) << 192, 10 ** (decimals0 + 18));
      uint256 priceUpperX192 =
        FullMath.mulDiv(priceTickUpper, (10 ** decimals1) << 192, 10 ** (decimals0 + 18));

      parsedParams.initSqrtPriceX96 = uint160(Math.sqrt(initPriceX192));
      parsedParams.tickLower = (
        TickMath.getTickAtSqrtPrice(uint160(Math.sqrt(priceLowerX192))) / parsedParams.tickSpacing
      ) * parsedParams.tickSpacing;
      parsedParams.tickUpper = (
        TickMath.getTickAtSqrtPrice(uint160(Math.sqrt(priceUpperX192))) / parsedParams.tickSpacing
          + 1
      ) * parsedParams.tickSpacing;
    }

    console.log('Raw params:');
    console.log('token0: %s', rawParams.token0);
    console.log('token1: %s', rawParams.token1);
    console.log('lpFee: %s', rawParams.lpFee);
    console.log('tickSpacing: %s', rawParams.tickSpacing);
    console.log('initPrice: %s', rawParams.initPrice);
    console.log('priceTickLower: %s', rawParams.priceTickLower);
    console.log('priceTickUpper: %s', rawParams.priceTickUpper);
    console.log('token0Amount: %s', rawParams.token0Amount);
    console.log('token1Amount: %s', rawParams.token1Amount);
    console.log('---------------------');
    console.log('Parsed params:');
    console.log('token0: %s', parsedParams.token0);
    console.log('token1: %s', parsedParams.token1);
    console.log('lpFee: %s', parsedParams.lpFee);
    console.log('tickSpacing: %s', parsedParams.tickSpacing);
    console.log('initSqrtPriceX96: %s', parsedParams.initSqrtPriceX96);
    console.log('tickLower: %s', parsedParams.tickLower);
    console.log('tickUpper: %s', parsedParams.tickUpper);
    console.log('token0Amount: %s', parsedParams.token0Amount);
    console.log('token1Amount: %s', parsedParams.token1Amount);
    console.log(
      'Decimals0: %s',
      parsedParams.token0 == address(0) ? 18 : IERC20Metadata(parsedParams.token0).decimals()
    );
    console.log(
      'Decimals1: %s',
      parsedParams.token1 == address(0) ? 18 : IERC20Metadata(parsedParams.token1).decimals()
    );
  }
}
