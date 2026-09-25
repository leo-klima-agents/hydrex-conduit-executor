// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {IKlimaVeTokenConduit} from "../src/interfaces/IKlimaVeTokenConduit.sol";
import {ISafeModuleManager} from "../src/interfaces/ISafeModuleManager.sol";
import {ModuleManager as UpstreamModuleManager} from "./upstream/safe/base/ModuleManager.sol";

contract SelectorsTest is Test {
    bytes4 internal constant VOTE = 0x6f816a20;
    bytes4 internal constant CLAIM_SWAP_AND_DISTRIBUTE = 0x786fb402;
    bytes4 internal constant EXEC_FROM_MODULE_RETURN_DATA = 0x5229073f;
    bytes32 internal constant EXECUTOR_ROLE = 0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63;

    string internal constant CLAIM_SIGNATURE =
        "claimSwapAndDistribute(uint256,address[],bytes[],address[],address[],address[],uint256,uint256)";

    function test_selectors_literals() public pure {
        assertEq(IKlimaVeTokenConduit.vote.selector, VOTE);
        assertEq(IKlimaVeTokenConduit.claimSwapAndDistribute.selector, CLAIM_SWAP_AND_DISTRIBUTE);
        assertEq(ISafeModuleManager.execTransactionFromModuleReturnData.selector, EXEC_FROM_MODULE_RETURN_DATA);
    }

    function test_selectors_keccak() public pure {
        assertEq(IKlimaVeTokenConduit.vote.selector, bytes4(keccak256("vote(address[],uint256[])")));
        assertEq(IKlimaVeTokenConduit.claimSwapAndDistribute.selector, bytes4(keccak256(bytes(CLAIM_SIGNATURE))));
        assertEq(
            ISafeModuleManager.execTransactionFromModuleReturnData.selector,
            bytes4(keccak256("execTransactionFromModuleReturnData(address,uint256,bytes,uint8)"))
        );
    }

    function test_executorRole_keccak() public pure {
        assertEq(keccak256("EXECUTOR_ROLE"), EXECUTOR_ROLE);
    }

    function test_selectors_upstreamSafeCompiled() public pure {
        assertEq(
            ISafeModuleManager.execTransactionFromModuleReturnData.selector,
            UpstreamModuleManager.execTransactionFromModuleReturnData.selector
        );
    }

    function test_selectors_upstreamConduitText() public view {
        string memory conduit = vm.readFile("test/upstream/hydrex/KlimaVeTokenConduit.sol");
        assertTrue(vm.contains(conduit, "bytes32 public constant EXECUTOR_ROLE = keccak256(\"EXECUTOR_ROLE\");"));
        assertTrue(
            vm.contains(
                conduit,
                "function vote(address[] calldata pools, uint256[] calldata weights) external onlyRole(EXECUTOR_ROLE) {"
            )
        );
        assertTrue(
            vm.contains(
                conduit,
                "function claimSwapAndDistribute(\n" "        uint256 veTokenId,\n"
                "        address[] calldata targets,\n" "        bytes[] calldata swaps,\n"
                "        address[] calldata feeAddresses,\n" "        address[] calldata bribeAddresses,\n"
                "        address[] calldata claimTokens,\n" "        uint256 retireTonnes,\n"
                "        uint256 maxKvcmIn\n" "    ) external onlyRole(EXECUTOR_ROLE) {"
            )
        );
        assertEq(_count(conduit, "onlyRole(EXECUTOR_ROLE)"), 2);
    }

    function test_selectors_upstreamSafeText() public view {
        string memory mm = vm.readFile("test/upstream/safe/base/ModuleManager.sol");
        assertTrue(
            vm.contains(
                mm,
                "function execTransactionFromModuleReturnData(\n" "        address to,\n" "        uint256 value,\n"
                "        bytes memory data,\n" "        Enum.Operation operation\n"
                "    ) public returns (bool success, bytes memory returnData) {"
            )
        );
        assertTrue(
            vm.contains(mm, "require(msg.sender != SENTINEL_MODULES && modules[msg.sender] != address(0), \"GS104\");")
        );
        string memory en = vm.readFile("test/upstream/safe/common/Enum.sol");
        assertTrue(vm.contains(en, "enum Operation {\n        Call,\n        DelegateCall\n    }"));
    }

    function test_selectors_upstreamMdTable() public view {
        string memory md = vm.readFile("test/upstream/UPSTREAM.md");
        _assertRow(md, "vote(address[],uint256[])", VOTE);
        _assertRow(md, CLAIM_SIGNATURE, CLAIM_SWAP_AND_DISTRIBUTE);
        _assertRow(md, "execTransactionFromModuleReturnData(address,uint256,bytes,uint8)", EXEC_FROM_MODULE_RETURN_DATA);
    }

    function _assertRow(string memory md, string memory signature, bytes4 selector) internal pure {
        string memory row = string.concat("| `", signature, "` | `", vm.toString(abi.encodePacked(selector)), "` |");
        assertTrue(vm.contains(md, row), string.concat("UPSTREAM.md row missing or stale: ", row));
    }

    function _count(string memory haystack, string memory needle) internal pure returns (uint256 n) {
        bytes memory h = bytes(haystack);
        bytes memory nd = bytes(needle);
        for (uint256 i; i + nd.length <= h.length; ++i) {
            bool hit = true;
            for (uint256 j; j < nd.length; ++j) {
                if (h[i + j] != nd[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) ++n;
        }
    }
}
