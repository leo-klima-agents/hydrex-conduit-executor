// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {HydrexCarbonImpactExecutor} from "../src/HydrexCarbonImpactExecutor.sol";

/// @notice CREATE2 deployment through forge's default deployer; a no-op once the address has code.
contract Deploy is Script {
    /// @dev Klima Safe, 3-of-5, Safe 1.3.0 L2.
    address public constant SAFE = 0xa79cd47655156b299762DFE92A67980805ce5a31;
    /// @dev Hydrex `KlimaVeTokenConduit`, verified and non-upgradeable.
    address public constant CONDUIT = 0xdE91885cF35ac57DF0c4A75c16862127dBe8317c;
    /// @dev The HSM keeper's address comes from hydrex-keeper-key's vendored record; test/Deploy.t.sol re-derives
    ///      it from the public key next to it.
    string public constant KEEPER_RECORD = "test/upstream/keeper-key/keeper.json";
    string public constant SALT_PREIMAGE = "klimaprotocol.com/HydrexCarbonImpactExecutor/v1";
    bytes32 public constant SALT = keccak256(bytes(SALT_PREIMAGE));

    function keeper() public view returns (address) {
        return vm.parseJsonAddress(vm.readFile(KEEPER_RECORD), ".address");
    }

    function constructorArgs() public view returns (bytes memory) {
        return abi.encode(SAFE, CONDUIT, keeper());
    }

    function initCode() public view returns (bytes memory) {
        return bytes.concat(type(HydrexCarbonImpactExecutor).creationCode, constructorArgs());
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
        console.log("HydrexCarbonImpactExecutor", deployed);
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
