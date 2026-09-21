// SPDX-FileCopyrightText: 2026 Klima Protocol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {KlimaConduitExecutor} from "../src/KlimaConduitExecutor.sol";
import {Deploy} from "./Deploy.s.sol";

/// @notice Writes verification/bytecode-hashes.json for the canonical deployment.
contract Hashes is Deploy {
    function run() external override returns (address predicted) {
        predicted = predict();
        string memory artifact = vm.readFile("out/KlimaConduitExecutor.sol/KlimaConduitExecutor.json");
        // The constructor requires code at SAFE and CONDUIT; this script runs on a local EVM, not a fork.
        vm.etch(SAFE, hex"00");
        vm.etch(CONDUIT, hex"00");
        KlimaConduitExecutor local = new KlimaConduitExecutor(SAFE, CONDUIT, KEEPER);

        string memory dep = "deployment";
        string memory depJson = vm.serializeAddress(dep, "safe", SAFE);
        depJson = vm.serializeAddress(dep, "conduit", CONDUIT);
        depJson = vm.serializeAddress(dep, "keeper", KEEPER);
        depJson = vm.serializeBytes(dep, "constructorArgs", constructorArgs());
        depJson = vm.serializeAddress(dep, "address", predicted);
        depJson = vm.serializeBytes32(dep, "runtimeKeccak", keccak256(address(local).code));

        string memory root = "hashes";
        string memory json = vm.serializeString(root, "contract", "src/KlimaConduitExecutor.sol:KlimaConduitExecutor");
        json = vm.serializeString(root, "solc", vm.parseJsonString(artifact, ".metadata.compiler.version"));
        json = vm.serializeAddress(root, "create2Deployer", CREATE2_FACTORY);
        json = vm.serializeString(root, "saltPreimage", SALT_PREIMAGE);
        json = vm.serializeBytes32(root, "salt", SALT);
        json = vm.serializeBytes32(root, "creationCodeKeccak", keccak256(type(KlimaConduitExecutor).creationCode));
        json = vm.serializeBytes32(
            root,
            "runtimeTemplateKeccak",
            keccak256(vm.getDeployedCode("KlimaConduitExecutor.sol:KlimaConduitExecutor"))
        );
        json = vm.serializeString(root, "deployment", depJson);
        vm.writeJson(json, "verification/bytecode-hashes.json");
    }
}
