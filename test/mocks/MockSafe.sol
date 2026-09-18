// SPDX-FileCopyrightText: 2026 Klima Protocol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Safe 1.3.0 `ModuleManager` semantics for the members this repo touches: the `GS104` module gate,
///         `execute` as a plain `call`/`delegatecall` with `gasleft()`, the two module events, and
///         `execTransactionFromModuleReturnData` returning the callee's return or revert data. `enableModule`
///         is open instead of `authorized` so tests can wire it directly.
contract MockSafe {
    event ExecutionFromModuleSuccess(address indexed module);
    event ExecutionFromModuleFailure(address indexed module);

    mapping(address module => bool enabled) public isModuleEnabled;

    address public lastTo;
    uint256 public lastValue;
    bytes public lastData;
    uint8 public lastOperation;
    uint256 public execCalls;

    function enableModule(address module) external {
        isModuleEnabled[module] = true;
    }

    function disableModule(address module) external {
        isModuleEnabled[module] = false;
    }

    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, uint8 operation)
        external
        virtual
        returns (bool success, bytes memory returnData)
    {
        require(isModuleEnabled[msg.sender], "GS104");
        (lastTo, lastValue, lastData, lastOperation) = (to, value, data, operation);
        execCalls++;
        if (operation == 1) {
            (success, returnData) = to.delegatecall(data);
        } else {
            (success, returnData) = to.call{value: value}(data);
        }
        if (success) emit ExecutionFromModuleSuccess(msg.sender);
        else emit ExecutionFromModuleFailure(msg.sender);
    }

    receive() external payable {}
}

/// @notice Reports failure with no return data and never calls anything, like a Safe whose inner call ran out
///         of gas or reverted without data.
contract FailingSafe is MockSafe {
    function execTransactionFromModuleReturnData(address, uint256, bytes memory, uint8)
        external
        virtual
        override
        returns (bool success, bytes memory returnData)
    {
        require(isModuleEnabled[msg.sender], "GS104");
        execCalls++;
        return (false, "");
    }
}
