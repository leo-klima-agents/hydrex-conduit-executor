// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice Safe 1.3.0 `ModuleManager` semantics for `execTransactionFromModuleReturnData`: the `GS104` gate, the
///         two module events and the callee's return or revert data. `enableModule` is unauthenticated.
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

/// @notice Reports failure with no return data without calling anything.
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
