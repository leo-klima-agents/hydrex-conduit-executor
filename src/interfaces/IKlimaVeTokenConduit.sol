// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

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
