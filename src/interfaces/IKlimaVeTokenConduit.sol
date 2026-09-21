// SPDX-FileCopyrightText: 2026 Klima Protocol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice The two `EXECUTOR_ROLE` members of Hydrex's `KlimaVeTokenConduit`, re-declared; nothing is imported.
interface IKlimaVeTokenConduit {
    function vote(address[] calldata pools, uint256[] calldata weights) external;

    function claimSwapAndDistribute(
        uint256 veTokenId,
        address[] calldata targets,
        bytes[] calldata swaps,
        address[] calldata feeAddresses,
        address[] calldata bribeAddresses,
        address[] calldata claimTokens,
        uint256 retireTonnes,
        uint256 maxKvcmIn
    ) external;
}
