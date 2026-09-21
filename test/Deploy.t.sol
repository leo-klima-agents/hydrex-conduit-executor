// SPDX-FileCopyrightText: 2026 Klima Protocol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {Deploy} from "../script/Deploy.s.sol";
import {KlimaConduitExecutor} from "../src/KlimaConduitExecutor.sol";

contract DeployTest is Test {
    Deploy internal d;

    function setUp() public {
        d = new Deploy();
        // The constructor requires code at SAFE and CONDUIT; on Base they are the live Safe and conduit.
        vm.etch(d.SAFE(), hex"00");
        vm.etch(d.CONDUIT(), hex"00");
    }

    function test_canonicalValues() public view {
        assertEq(d.SAFE(), 0xa79cd47655156b299762DFE92A67980805ce5a31);
        assertEq(d.CONDUIT(), 0xdE91885cF35ac57DF0c4A75c16862127dBe8317c);
        assertTrue(d.KEEPER() != address(0));
        assertTrue(d.KEEPER() != d.SAFE() && d.KEEPER() != d.CONDUIT());
        assertEq(d.KEEPER_PLACEHOLDER(), 0x000000000000000000000000000000000000dEaD);
        assertEq(d.SALT(), keccak256("klimaprotocol.com/KlimaConduitExecutor/v1"));
    }

    /// @dev The address is a function of the constructor arguments, so a placeholder deployment cannot occupy
    ///      the real keeper's address, and the salt never needs to change for it.
    function test_predict_dependsOnKeeper() public view {
        bytes memory otherArgs = abi.encode(d.SAFE(), d.CONDUIT(), address(0xB0B));
        address other = vm.computeCreate2Address(
            d.SALT(), keccak256(bytes.concat(type(KlimaConduitExecutor).creationCode, otherArgs)), CREATE2_FACTORY
        );
        assertTrue(other != d.predict());
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

    function test_run_refusesPlaceholderOutsideTests() public {
        if (d.KEEPER() != d.KEEPER_PLACEHOLDER()) return;
        // `forge test` is the TestGroup context, where `run` deploys the placeholder; a script context refuses.
        assertTrue(vm.isContext(VmSafe.ForgeContext.TestGroup));
        assertFalse(vm.isContext(VmSafe.ForgeContext.ScriptGroup));
        assertEq(d.run(), d.predict());
    }

    function test_run_failsWithoutDeployer() public {
        vm.etch(CREATE2_FACTORY, "");
        vm.expectRevert(bytes("CREATE2 deployer not present"));
        d.run();
    }
}
