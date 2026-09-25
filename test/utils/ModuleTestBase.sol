// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {HydrexCarbonImpactExecutor} from "../../src/HydrexCarbonImpactExecutor.sol";

/// @notice Shared by the mock and fork suites. `_claim` is the smallest claim the conduit accepts.
abstract contract ModuleTestBase is Test {
    HydrexCarbonImpactExecutor internal module;

    function _claim(address caller, uint256 tokenId) internal {
        vm.prank(caller);
        module.claimSwapAndDistribute(
            tokenId, new address[](0), new bytes[](0), new address[](0), new address[](0), new address[](0), 0, 0
        );
    }
}
