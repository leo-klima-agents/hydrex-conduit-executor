// SPDX-FileCopyrightText: 2026 Klima Protocol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice The one Safe 1.3.0 `ModuleManager` member this module calls. `operation` is Safe's `Enum.Operation`,
///         a `uint8` in the ABI: 0 is `Call`, 1 is `DelegateCall`.
interface ISafeModuleManager {
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bool success, bytes memory returnData);
}
