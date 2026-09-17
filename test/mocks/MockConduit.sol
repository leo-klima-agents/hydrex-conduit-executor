// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract MockConduit {
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error Boom(uint256 code);

    mapping(address account => bool) public isExecutor;

    address public lastSender;
    bytes public lastCalldata;
    uint256 public lastValue;
    uint256 public voteCalls;
    uint256 public claimCalls;

    bool public shouldRevert;
    bytes public revertData;

    function grantExecutor(address account) external {
        isExecutor[account] = true;
    }

    function revokeExecutor(address account) external {
        isExecutor[account] = false;
    }

    function revertWith(bytes calldata data) external {
        shouldRevert = true;
        revertData = data;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return role == EXECUTOR_ROLE && isExecutor[account];
    }

    function vote(address[] calldata pools, uint256[] calldata weights) external payable {
        _gate();
        require(pools.length == weights.length, "Pools/weights length mismatch");
        voteCalls++;
    }

    function claimSwapAndDistribute(
        uint256,
        address[] calldata,
        bytes[] calldata,
        address[] calldata,
        address[] calldata,
        address[] calldata,
        uint256,
        uint256
    ) external payable {
        _gate();
        claimCalls++;
    }

    function _gate() internal {
        if (!isExecutor[msg.sender]) revert AccessControlUnauthorizedAccount(msg.sender, EXECUTOR_ROLE);
        if (shouldRevert) {
            bytes memory data = revertData;
            assembly ("memory-safe") {
                revert(add(data, 0x20), mload(data))
            }
        }
        lastSender = msg.sender;
        lastCalldata = msg.data;
        lastValue = msg.value;
    }
}
