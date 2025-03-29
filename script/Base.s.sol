// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';
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

  function setUp() public {
    path = string.concat(vm.projectRoot(), '/script/configs/');

    uint256 _chainId;
    assembly {
      _chainId := chainid()
    }
    chainId = vm.toString(_chainId);
  }

  function _msgSender() internal returns (address msgSender) {
    vm.startBroadcast();
    msgSender = msg.sender;
    vm.stopBroadcast();
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
    string memory json = _getJsonString(key);
    json.serialize(chainId, value);
    vm.writeJson(json, string.concat(path, key, '.json'));
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
