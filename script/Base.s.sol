// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import 'openzeppelin-contracts/contracts/utils/Address.sol';

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
  address[] operators;
  address quoteSigner;
  address surplusRecipient;

  function setUp() public virtual {
    path = string.concat(vm.projectRoot(), '/script/config/');

    uint256 _chainId;
    assembly {
      _chainId := chainid()
    }
    chainId = vm.toString(_chainId);

    owner = _readAddress('owner');
    operators = _readAddressArray('operators');
    quoteSigner = _readAddress('quote-signer');
    surplusRecipient = _readAddress('surplus-recipient');
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
}
