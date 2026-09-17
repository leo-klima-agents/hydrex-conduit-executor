// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {KlimaVeTokenConduitExecutor} from "../src/KlimaVeTokenConduitExecutor.sol";

contract Deploy is Script {
    address public constant SAFE = 0x17f513C024C1C67db050258ba569c714a9CF1B12;
    address public constant CONDUIT = 0xdE91885cF35ac57DF0c4A75c16862127dBe8317c;
    string public constant KEEPER_RECORD = "test/upstream/keeper/keeper.json";
    string public constant SALT_PREIMAGE = "klimaprotocol.com/KlimaVeTokenConduitExecutor/v1";
    bytes32 public constant SALT = keccak256(bytes(SALT_PREIMAGE));

    function keeper() public view returns (address) {
        return vm.parseJsonAddress(vm.readFile(KEEPER_RECORD), ".address");
    }

    function constructorArgs() public view returns (bytes memory) {
        return abi.encode(SAFE, CONDUIT, keeper());
    }

    function initCode() public view returns (bytes memory) {
        return bytes.concat(type(KlimaVeTokenConduitExecutor).creationCode, constructorArgs());
    }

    function predict() public view returns (address) {
        return _predict(initCode());
    }

    function _predict(bytes memory code) internal pure returns (address) {
        return vm.computeCreate2Address(SALT, keccak256(code), CREATE2_FACTORY);
    }

    function run() external virtual returns (address deployed) {
        require(CREATE2_FACTORY.code.length != 0, "CREATE2 deployer not present");
        bytes memory code = initCode();
        deployed = _predict(code);
        console.log("KlimaVeTokenConduitExecutor", deployed);
        if (deployed.code.length != 0) {
            console.log("already deployed");
            return deployed;
        }
        vm.startBroadcast();
        (bool ok,) = CREATE2_FACTORY.call(bytes.concat(SALT, code));
        vm.stopBroadcast();
        require(ok && deployed.code.length != 0, "CREATE2 deploy failed");
        console.log("deployed");
    }
}
