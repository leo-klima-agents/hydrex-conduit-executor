// SPDX-FileCopyrightText: 2026 Klima Protocol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../script/Deploy.s.sol";
import {KlimaConduitExecutor} from "../src/KlimaConduitExecutor.sol";

contract DeployTest is Test {
    Deploy internal d;

    function setUp() public {
        d = new Deploy();
    }

    function test_canonicalValues() public view {
        assertEq(d.SAFE(), 0xa79cd47655156b299762DFE92A67980805ce5a31);
        assertEq(d.CONDUIT(), 0xdE91885cF35ac57DF0c4A75c16862127dBe8317c);
        assertTrue(d.KEEPER() != address(0));
        assertTrue(d.KEEPER() != d.SAFE() && d.KEEPER() != d.CONDUIT());
        assertEq(d.SALT(), keccak256("klimaprotocol.com/KlimaConduitExecutor/v1"));
    }

    function test_recordMatchesScript() public {
        string memory json = vm.readFile("verification/bytecode-hashes.json");
        assertEq(vm.parseJsonString(json, ".contract"), "src/KlimaConduitExecutor.sol:KlimaConduitExecutor");
        assertEq(vm.parseJsonAddress(json, ".create2Deployer"), CREATE2_FACTORY);
        assertEq(vm.parseJsonString(json, ".saltPreimage"), d.SALT_PREIMAGE());
        assertEq(vm.parseJsonBytes32(json, ".salt"), d.SALT());
        assertEq(vm.parseJsonBytes32(json, ".creationCodeKeccak"), keccak256(type(KlimaConduitExecutor).creationCode));
        assertEq(
            vm.parseJsonBytes32(json, ".runtimeTemplateKeccak"),
            keccak256(vm.getDeployedCode("KlimaConduitExecutor.sol:KlimaConduitExecutor"))
        );
        assertEq(vm.parseJsonAddress(json, ".deployment.safe"), d.SAFE());
        assertEq(vm.parseJsonAddress(json, ".deployment.conduit"), d.CONDUIT());
        assertEq(vm.parseJsonAddress(json, ".deployment.keeper"), d.KEEPER());
        assertEq(vm.parseJsonBytes(json, ".deployment.constructorArgs"), d.constructorArgs());
        assertEq(vm.parseJsonAddress(json, ".deployment.address"), d.predict());
        assertEq(
            vm.parseJsonBytes32(json, ".deployment.runtimeKeccak"),
            keccak256(address(new KlimaConduitExecutor(d.SAFE(), d.CONDUIT(), d.KEEPER())).code)
        );
    }

    function test_run_deploysAtPredictedAddress() public {
        address predicted = d.predict();
        assertEq(predicted.code.length, 0);

        assertEq(d.run(), predicted);

        assertEq(KlimaConduitExecutor(predicted).SAFE(), d.SAFE());
        assertEq(KlimaConduitExecutor(predicted).CONDUIT(), d.CONDUIT());
        assertEq(KlimaConduitExecutor(predicted).KEEPER(), d.KEEPER());
    }

    function test_run_isIdempotent() public {
        address first = d.run();
        bytes32 codehash = first.codehash;

        assertEq(d.run(), first);
        assertEq(first.codehash, codehash);
    }

    function test_run_failsWithoutDeployer() public {
        vm.etch(CREATE2_FACTORY, "");
        vm.expectRevert(bytes("CREATE2 deployer not present"));
        d.run();
    }
}
