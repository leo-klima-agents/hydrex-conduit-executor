// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IKlimaVeTokenConduit} from "./interfaces/IKlimaVeTokenConduit.sol";
import {ISafeModuleManager} from "./interfaces/ISafeModuleManager.sol";

/// @title KlimaConduitExecutor
/// @notice Safe module that lets one keeper key call `vote` and `claimSwapAndDistribute` on one Hydrex conduit
///         on the Safe's behalf, and nothing else. Every call is a plain `Call` to `CONDUIT` with zero value and
///         calldata this contract encodes itself. No storage, no owner, no upgrade path, no ETH. Implements
///         `IKlimaVeTokenConduit` so the two signatures are the conduit's by construction.
contract KlimaConduitExecutor is IKlimaVeTokenConduit {
    address public immutable SAFE;
    address public immutable CONDUIT;
    address public immutable KEEPER;

    error ZeroAddress();
    error NotAContract();
    error NotKeeper();
    error ExecutionFailed();

    /// @dev `safe` and `conduit` must hold code: a `Call` to an empty address succeeds silently, so a mistyped
    ///      conduit would make every vote a no-op that reports success.
    constructor(address safe, address conduit, address keeper) {
        if (safe == address(0) || conduit == address(0) || keeper == address(0)) revert ZeroAddress();
        if (safe.code.length == 0 || conduit.code.length == 0) revert NotAContract();
        SAFE = safe;
        CONDUIT = conduit;
        KEEPER = keeper;
    }

    /// @notice `CONDUIT.vote(pools, weights)` from the Safe. The Voter checks gauge liveness and voting power.
    function vote(address[] calldata pools, uint256[] calldata weights) external {
        _exec(abi.encodeCall(IKlimaVeTokenConduit.vote, (pools, weights)));
    }

    /// @notice `CONDUIT.claimSwapAndDistribute(...)` from the Safe. The conduit checks routers, output tokens
    ///         and the recipient; rewards never pass through this contract or the Safe.
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

    /// @dev Keeper gate, then `Call` to `CONDUIT` through the Safe. A failed call re-raises the conduit's own
    ///      revert data; a failure without data becomes `ExecutionFailed`. The Safe's own reverts, such as
    ///      `GS104` when this module is not enabled, propagate unchanged.
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
