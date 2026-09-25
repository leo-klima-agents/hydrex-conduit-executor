// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../script/Deploy.s.sol";
import {KlimaVeTokenConduitExecutor} from "../src/KlimaVeTokenConduitExecutor.sol";

contract DeployTest is Test {
    Deploy internal d;

    function setUp() public {
        d = new Deploy();
        vm.etch(d.SAFE(), hex"00");
        vm.etch(d.CONDUIT(), hex"00");
    }

    function test_canonicalValues() public view {
        assertEq(d.SAFE(), 0x17f513C024C1C67db050258ba569c714a9CF1B12);
        assertEq(d.CONDUIT(), 0xdE91885cF35ac57DF0c4A75c16862127dBe8317c);
        assertEq(d.keeper(), 0x625CF6663d9D090535FBd57680bFFE6fA0262434);
        assertEq(d.KEEPER_RECORD(), "test/upstream/keeper/keeper.json");
        assertEq(d.SALT(), keccak256("klimaprotocol.com/KlimaVeTokenConduitExecutor/v1"));
    }

    function test_keeperRecord_describesTheHsmKey() public view {
        string memory json = vm.readFile(d.KEEPER_RECORD());
        assertEq(vm.parseJsonString(json, ".algorithm"), "EC_SIGN_SECP256K1_SHA256");
        assertEq(vm.parseJsonString(json, ".protectionLevel"), "HSM");
        string memory version = vm.parseJsonString(json, ".version");
        assertEq(version, string.concat(vm.parseJsonString(json, ".key"), "/cryptoKeyVersions/1"));
        assertTrue(vm.contains(version, "/keyRings/hydrex-keeper/cryptoKeys/hydrex-keeper-v1/"));
        assertEq(vm.parseJsonAddress(json, ".address"), d.keeper());
    }

    function test_keeperRecord_addressDerivesFromPublicKey() public view {
        bytes memory der = _pemToDer(vm.readFile("test/upstream/keeper/keeper.pem"));
        assertEq(der.length, 88, "secp256k1 SPKI is 88 bytes");
        bytes memory prefix = hex"3056301006072a8648ce3d020106052b8104000a03420004";
        for (uint256 i; i < prefix.length; ++i) {
            assertEq(der[i], prefix[i], "not an uncompressed secp256k1 SubjectPublicKeyInfo");
        }
        bytes memory xy = new bytes(64);
        for (uint256 i; i < 64; ++i) {
            xy[i] = der[24 + i];
        }
        address derived = address(uint160(uint256(keccak256(xy))));
        assertEq(derived, d.keeper());
        assertEq(derived, 0x625CF6663d9D090535FBd57680bFFE6fA0262434);
    }

    function test_predict_dependsOnKeeper() public view {
        bytes memory otherArgs = abi.encode(d.SAFE(), d.CONDUIT(), address(0xB0B));
        address other = vm.computeCreate2Address(
            d.SALT(),
            keccak256(bytes.concat(type(KlimaVeTokenConduitExecutor).creationCode, otherArgs)),
            CREATE2_FACTORY
        );
        assertTrue(other != d.predict());
    }

    function _pemToDer(string memory pem) internal pure returns (bytes memory der) {
        bytes memory raw = bytes(pem);
        bytes memory b64 = new bytes(raw.length);
        uint256 n;
        bool inBody;
        for (uint256 i; i < raw.length; ++i) {
            bytes1 c = raw[i];
            if (c == "-") {
                while (i < raw.length && raw[i] != "\n") ++i;
                if (inBody) break;
                inBody = true;
                continue;
            }
            if (!inBody || c == "\n" || c == "\r" || c == "=") continue;
            b64[n++] = c;
        }
        require(n % 4 != 1, "bad base64 length");
        der = new bytes((n * 3) / 4);
        uint256 out;
        uint256 acc;
        uint256 bits;
        for (uint256 i; i < n; ++i) {
            acc = (acc << 6) | _b64(b64[i]);
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                der[out++] = bytes1(uint8(acc >> bits));
                acc &= (1 << bits) - 1;
            }
        }
        require(out == der.length, "base64 decode length");
    }

    function _b64(bytes1 c) internal pure returns (uint256) {
        if (c >= "A" && c <= "Z") return uint8(c) - 65;
        if (c >= "a" && c <= "z") return uint8(c) - 97 + 26;
        if (c >= "0" && c <= "9") return uint8(c) - 48 + 52;
        if (c == "+") return 62;
        if (c == "/") return 63;
        revert("bad base64 character");
    }

    function test_recordMatchesScript() public {
        string memory json = vm.readFile("verification/bytecode-hashes.json");
        assertEq(
            vm.parseJsonString(json, ".contract"), "src/KlimaVeTokenConduitExecutor.sol:KlimaVeTokenConduitExecutor"
        );
        assertEq(vm.parseJsonAddress(json, ".create2Deployer"), CREATE2_FACTORY);
        assertEq(vm.parseJsonString(json, ".saltPreimage"), d.SALT_PREIMAGE());
        assertEq(vm.parseJsonBytes32(json, ".salt"), d.SALT());
        assertEq(
            vm.parseJsonBytes32(json, ".creationCodeKeccak"), keccak256(type(KlimaVeTokenConduitExecutor).creationCode)
        );
        assertEq(
            vm.parseJsonBytes32(json, ".runtimeTemplateKeccak"),
            keccak256(vm.getDeployedCode("KlimaVeTokenConduitExecutor.sol:KlimaVeTokenConduitExecutor"))
        );
        assertEq(vm.parseJsonAddress(json, ".deployment.safe"), d.SAFE());
        assertEq(vm.parseJsonAddress(json, ".deployment.conduit"), d.CONDUIT());
        assertEq(vm.parseJsonAddress(json, ".deployment.keeper"), d.keeper());
        assertEq(vm.parseJsonBytes(json, ".deployment.constructorArgs"), d.constructorArgs());
        assertEq(vm.parseJsonAddress(json, ".deployment.address"), d.predict());
        assertEq(
            vm.parseJsonBytes32(json, ".deployment.runtimeKeccak"),
            keccak256(address(new KlimaVeTokenConduitExecutor(d.SAFE(), d.CONDUIT(), d.keeper())).code)
        );
    }

    function test_run_deploysAtPredictedAddress() public {
        address predicted = d.predict();
        assertEq(predicted.code.length, 0);

        assertEq(d.run(), predicted);

        assertEq(KlimaVeTokenConduitExecutor(predicted).SAFE(), d.SAFE());
        assertEq(KlimaVeTokenConduitExecutor(predicted).CONDUIT(), d.CONDUIT());
        assertEq(KlimaVeTokenConduitExecutor(predicted).KEEPER(), d.keeper());
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
