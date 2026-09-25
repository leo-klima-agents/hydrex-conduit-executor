// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

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
        assertEq(d.keeper(), 0x625CF6663d9D090535FBd57680bFFE6fA0262434);
        assertEq(d.KEEPER_RECORD(), "test/upstream/keeper-key/keeper.json");
        assertEq(d.SALT(), keccak256("klimaprotocol.com/KlimaConduitExecutor/v1"));
    }

    /// @dev The vendored record is what hydrex-keeper-key wrote for key version 1: HSM, secp256k1.
    function test_keeperRecord_describesTheHsmKey() public view {
        string memory json = vm.readFile(d.KEEPER_RECORD());
        assertEq(vm.parseJsonString(json, ".algorithm"), "EC_SIGN_SECP256K1_SHA256");
        assertEq(vm.parseJsonString(json, ".protectionLevel"), "HSM");
        string memory version = vm.parseJsonString(json, ".version");
        assertEq(version, string.concat(vm.parseJsonString(json, ".key"), "/cryptoKeyVersions/1"));
        assertTrue(vm.contains(version, "/keyRings/hydrex-keeper/cryptoKeys/hydrex-keeper-v1/"));
        assertEq(vm.parseJsonAddress(json, ".address"), d.keeper());
    }

    /// @dev The address is not taken on trust from the JSON: it is re-derived here from the vendored public key.
    ///      PEM -> base64 -> DER SubjectPublicKeyInfo -> uncompressed point -> keccak256 -> last 20 bytes.
    function test_keeperRecord_addressDerivesFromPublicKey() public view {
        bytes memory der = _pemToDer(vm.readFile("test/upstream/keeper-key/keeper.pem"));
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

    /// @dev The address is a function of the constructor arguments, so a different key gets a different address
    ///      under the same salt.
    function test_predict_dependsOnKeeper() public view {
        bytes memory otherArgs = abi.encode(d.SAFE(), d.CONDUIT(), address(0xB0B));
        address other = vm.computeCreate2Address(
            d.SALT(), keccak256(bytes.concat(type(KlimaConduitExecutor).creationCode, otherArgs)), CREATE2_FACTORY
        );
        assertTrue(other != d.predict());
    }

    function _pemToDer(string memory pem) internal pure returns (bytes memory der) {
        bytes memory raw = bytes(pem);
        bytes memory b64 = new bytes(raw.length);
        uint256 n;
        bool inBody;
        // Keep the base64 characters between the BEGIN and END lines; drop headers, newlines and padding.
        for (uint256 i; i < raw.length; ++i) {
            bytes1 c = raw[i];
            if (c == "-") {
                // A header line: skip to its end. The first one starts the body, the second one ends it.
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
        assertEq(vm.parseJsonAddress(json, ".deployment.keeper"), d.keeper());
        assertEq(vm.parseJsonBytes(json, ".deployment.constructorArgs"), d.constructorArgs());
        assertEq(vm.parseJsonAddress(json, ".deployment.address"), d.predict());
        assertEq(
            vm.parseJsonBytes32(json, ".deployment.runtimeKeccak"),
            keccak256(address(new KlimaConduitExecutor(d.SAFE(), d.CONDUIT(), d.keeper())).code)
        );
    }

    function test_run_deploysAtPredictedAddress() public {
        address predicted = d.predict();
        assertEq(predicted.code.length, 0);

        assertEq(d.run(), predicted);

        assertEq(KlimaConduitExecutor(predicted).SAFE(), d.SAFE());
        assertEq(KlimaConduitExecutor(predicted).CONDUIT(), d.CONDUIT());
        assertEq(KlimaConduitExecutor(predicted).KEEPER(), d.keeper());
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
