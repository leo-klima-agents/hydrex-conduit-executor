// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IKlimaVeTokenConduit} from "./interfaces/IKlimaVeTokenConduit.sol";
import {ISafeModuleManager} from "./interfaces/ISafeModuleManager.sol";

/// @notice Safe module that lets `KEEPER` call `vote` and `claimSwapAndDistribute` on `CONDUIT` as the Safe.
contract KlimaVeTokenConduitExecutor is IKlimaVeTokenConduit {
    address public immutable SAFE;
    address public immutable CONDUIT;
    address public immutable KEEPER;

    error ZeroAddress();
    error NotAContract();
    error NotKeeper();
    error ExecutionFailed();

    constructor(address safe, address conduit, address keeper) {
        if (safe == address(0) || conduit == address(0) || keeper == address(0)) revert ZeroAddress();
        if (safe.code.length == 0 || conduit.code.length == 0) revert NotAContract();
        SAFE = safe;
        CONDUIT = conduit;
        KEEPER = keeper;
    }

    function vote(address[] calldata pools, uint256[] calldata weights) external {
        _exec(abi.encodeCall(IKlimaVeTokenConduit.vote, (pools, weights)));
    }

    function claimSwapAndDistribute(
        uint256 veTokenId,
        address[] calldata targets,
        bytes[] calldata swaps,
        address[] calldata feeAddresses,
        address[] calldata bribeAddresses,
        address[] calldata claimTokens,
        uint256 retireTonnes,
        uint256 maxKvcmIn
    ) external {
        _exec(
            abi.encodeCall(
                IKlimaVeTokenConduit.claimSwapAndDistribute,
                (veTokenId, targets, swaps, feeAddresses, bribeAddresses, claimTokens, retireTonnes, maxKvcmIn)
            )
        );
    }

    function _exec(bytes memory data) internal {
        if (msg.sender != KEEPER) revert NotKeeper();
        (bool ok, bytes memory ret) = ISafeModuleManager(SAFE).execTransactionFromModuleReturnData(CONDUIT, 0, data, 0);
        if (ok) return;
        if (ret.length == 0) revert ExecutionFailed();
        assembly ("memory-safe") {
            revert(add(ret, 0x20), mload(ret))
        }
    }
}
