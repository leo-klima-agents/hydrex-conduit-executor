// SPDX-FileCopyrightText: 2026 Klima Protocol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {KlimaConduitExecutor} from "../src/KlimaConduitExecutor.sol";

/// @notice CREATE2 deployment through forge's default deployer; a no-op once the address has code.
contract Deploy is Script {
    /// @dev Klima Safe, 3-of-5, Safe 1.3.0 L2.
    address public constant SAFE = 0xa79cd47655156b299762DFE92A67980805ce5a31;
    /// @dev Hydrex `KlimaVeTokenConduit`, verified and non-upgradeable.
    address public constant CONDUIT = 0xdE91885cF35ac57DF0c4A75c16862127dBe8317c;
    /// @dev The HSM-held keeper key. `KEEPER_PLACEHOLDER` until that key exists; `run` refuses to deploy it.
    ///      Replace, run `script/refresh-verification.sh`, commit, then deploy. The CREATE2 address is a function
    ///      of the constructor arguments, so the real keeper gets its own address under the same salt.
    address public constant KEEPER = 0x000000000000000000000000000000000000dEaD;
    address public constant KEEPER_PLACEHOLDER = 0x000000000000000000000000000000000000dEaD;
    string public constant SALT_PREIMAGE = "klimaprotocol.com/KlimaConduitExecutor/v1";
    bytes32 public constant SALT = keccak256(bytes(SALT_PREIMAGE));

    function constructorArgs() public pure returns (bytes memory) {
        return abi.encode(SAFE, CONDUIT, KEEPER);
    }

    function initCode() public pure returns (bytes memory) {
        return bytes.concat(type(KlimaConduitExecutor).creationCode, constructorArgs());
    }

    function predict() public pure returns (address) {
        return _predict(initCode());
    }

    function _predict(bytes memory code) internal pure returns (address) {
        return vm.computeCreate2Address(SALT, keccak256(code), CREATE2_FACTORY);
    }

    function run() external virtual returns (address deployed) {
        // Tests exercise `run` with the placeholder; a script (dry run, broadcast or resume) never may.
        if (vm.isContext(VmSafe.ForgeContext.ScriptGroup)) {
            require(KEEPER != KEEPER_PLACEHOLDER, "KEEPER is the placeholder");
        }
        require(CREATE2_FACTORY.code.length != 0, "CREATE2 deployer not present");
        bytes memory code = initCode();
        deployed = _predict(code);
        console.log("KlimaConduitExecutor", deployed);
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
