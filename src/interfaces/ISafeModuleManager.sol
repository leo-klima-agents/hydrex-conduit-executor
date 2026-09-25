// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Safe 1.3.0 `ModuleManager`. `operation` is `Enum.Operation`: 0 is `Call`, 1 is `DelegateCall`.
interface ISafeModuleManager {
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bool success, bytes memory returnData);
}
