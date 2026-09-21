// SPDX-FileCopyrightText: 2026 Klima Protocol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {KlimaConduitExecutor} from "../../src/KlimaConduitExecutor.sol";

/// @notice Shared by the mock and fork suites: the module under test and a claim with no swaps, claims or
///         retirement, the smallest call the conduit accepts.
abstract contract ModuleTestBase is Test {
    KlimaConduitExecutor internal module;

    function _claim(address caller, uint256 tokenId) internal {
        vm.prank(caller);
        module.claimSwapAndDistribute(
            tokenId, new address[](0), new bytes[](0), new address[](0), new address[](0), new address[](0), 0, 0
        );
    }
}
