// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {KlimaVeTokenConduitExecutor} from "../../src/KlimaVeTokenConduitExecutor.sol";

abstract contract ModuleTestBase is Test {
    KlimaVeTokenConduitExecutor internal module;

    function _claim(address caller, uint256 tokenId) internal {
        vm.prank(caller);
        module.claimSwapAndDistribute(
            tokenId, new address[](0), new bytes[](0), new address[](0), new address[](0), new address[](0), 0, 0
        );
    }
}
