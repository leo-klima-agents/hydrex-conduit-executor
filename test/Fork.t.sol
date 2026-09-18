// SPDX-FileCopyrightText: 2026 Klima Protocol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test, Vm} from "forge-std/Test.sol";

import {KlimaConduitExecutor} from "../src/KlimaConduitExecutor.sol";
import {IKlimaVeTokenConduit} from "../src/interfaces/IKlimaVeTokenConduit.sol";

interface IAccessControl {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
}

interface ISafe {
    function VERSION() external view returns (string memory);
    function enableModule(address module) external;
    function isModuleEnabled(address module) external view returns (bool);
    function getModulesPaginated(address start, uint256 pageSize) external view returns (address[] memory, address);
}

interface IVoter {
    function _epochTimestamp() external view returns (uint256);
    function lastVoted(address voter) external view returns (uint256);
    function poolVoteLength(address voter) external view returns (uint256);
    function poolVote(address voter, uint256 index) external view returns (address);
    function votes(address voter, address pool) external view returns (uint256);
}

interface IVotingEscrow {
    function getPastVotes(address account, uint256 timestamp) external view returns (uint256);
    function getLockDelegatee(uint256 tokenId) external view returns (address);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Base mainnet, gated on `BASE_RPC_URL`. Wires the live Safe and conduit the way the README describes
///         (Hydrex grants, the Safe enables, the keeper calls) and checks the effect on the live Voter. Pins the
///         conduit's code and the Safe's singleton so an upgrade or migration on either side fails CI.
contract ForkTest is Test {
    address internal constant SAFE = 0xa79cd47655156b299762DFE92A67980805ce5a31;
    address internal constant CONDUIT = 0xdE91885cF35ac57DF0c4A75c16862127dBe8317c;
    address internal constant VOTER = 0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b;
    address internal constant VE = 0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1;
    address internal constant HYDREX_ADMIN = 0x74266f2b206D1359B83fc74949EF07176FB3AE03;
    address internal constant HYDREX_KEEPER = 0x1681b1d40AB2fb81F8a1dd28b56baFfbB869a214;
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @dev Safe 1.3.0 `GnosisSafeL2`, the EIP-155 deployment.
    address internal constant SAFE_SINGLETON = 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA;
    bytes32 internal constant CONDUIT_CODEHASH = 0x0d67cd335e3ae9cde256cf399f819a3ea2b9c248b0336840a3b20a2ee82c192e;

    /// @dev Friday 2026-09-18, second day of the epoch that started Thursday 2026-09-17 00:00 UTC.
    uint256 internal constant BLOCK = 51_477_372;
    uint256 internal constant EPOCH_START = 1_789_603_200;
    uint256 internal constant CONDUIT_POWER = 901_467_812_512_428_290_739_293;

    /// @dev The block before the keeper's 2026-09-09 vote, tx
    ///      0x6766749800fbc54c5cf134b3fd15a2456a57115b8319be995a48693406121607, and the votes it recorded.
    uint256 internal constant REPLAY_BLOCK = 51_082_978;
    uint256 internal constant REPLAY_EPOCH_START = 1_788_393_600;
    uint256 internal constant REPLAY_POWER = 949_625_930_479_905_743_892_671;
    uint256[3] internal replayVotes =
        [uint256(702_723_188_555_130_250_480_576), 161_436_408_181_583_976_461_754, 85_466_333_743_191_516_950_340];

    /// @dev A Safe-owned veNFT delegated to the conduit.
    uint256 internal constant SAFE_TOKEN_ID = 14_247;

    address internal keeper;
    KlimaConduitExecutor internal module;
    address[] internal pools;
    uint256[] internal weights;

    string internal rpc;

    function setUp() public {
        rpc = vm.envOr("BASE_RPC_URL", string(""));
        vm.skip(bytes(rpc).length == 0);

        keeper = makeAddr("hsm keeper");
        pools.push(0x7796fc53B75960A9762Ba267c19F5da9868B7853);
        pools.push(0x9849E92f29a9d3b89fe09694746E7AcF52bBc37D);
        pools.push(0x51f0B932855986B0E621c9D4DB6Eee1f4644D3D2);
        weights.push(74);
        weights.push(17);
        weights.push(9);
    }

    function _fork(uint256 blockNumber) internal {
        vm.createSelectFork(rpc, blockNumber);
        assertEq(block.chainid, 8453);
        module = new KlimaConduitExecutor(SAFE, CONDUIT, keeper);
    }

    function _grant() internal {
        vm.prank(HYDREX_ADMIN);
        IAccessControl(CONDUIT).grantRole(EXECUTOR_ROLE, SAFE);
    }

    function _enable() internal {
        vm.prank(SAFE);
        ISafe(SAFE).enableModule(address(module));
    }

    function _wire() internal {
        _grant();
        _enable();
    }

    function _claim(address caller, uint256 tokenId) internal {
        vm.prank(caller);
        module.claimSwapAndDistribute(
            tokenId, new address[](0), new bytes[](0), new address[](0), new address[](0), new address[](0), 0, 0
        );
    }

    /* ----------------------------------------------------------------------------------------------------------
                                                       pins
    ---------------------------------------------------------------------------------------------------------- */

    function test_pin_conduitCode() public {
        _fork(BLOCK);
        assertEq(CONDUIT.codehash, CONDUIT_CODEHASH);
        assertEq(keccak256(CONDUIT.code), CONDUIT_CODEHASH);
    }

    function test_pin_safeSingleton() public {
        _fork(BLOCK);
        assertEq(address(uint160(uint256(vm.load(SAFE, bytes32(0))))), SAFE_SINGLETON);
        assertEq(ISafe(SAFE).VERSION(), "1.3.0");
        assertEq(SAFE_SINGLETON.codehash, 0x21842597390c4c6e3c1239e434a682b054bd9548eee5e9b1d6a4482731023c0f);
    }

    function test_pin_startingState() public {
        _fork(BLOCK);
        assertTrue(IAccessControl(CONDUIT).hasRole(bytes32(0), HYDREX_ADMIN), "Hydrex admin lost DEFAULT_ADMIN_ROLE");
        assertTrue(IAccessControl(CONDUIT).hasRole(EXECUTOR_ROLE, HYDREX_KEEPER));
        assertFalse(IAccessControl(CONDUIT).hasRole(EXECUTOR_ROLE, SAFE));
        assertFalse(IAccessControl(CONDUIT).hasRole(EXECUTOR_ROLE, address(module)));
        assertFalse(ISafe(SAFE).isModuleEnabled(address(module)));
        (address[] memory modules,) = ISafe(SAFE).getModulesPaginated(address(1), 10);
        assertEq(modules.length, 0, "the Safe already has a module");
        assertEq(IVoter(VOTER)._epochTimestamp(), EPOCH_START);
        assertEq(IVotingEscrow(VE).getPastVotes(CONDUIT, EPOCH_START), CONDUIT_POWER);
        assertEq(IVotingEscrow(VE).ownerOf(SAFE_TOKEN_ID), SAFE);
        assertEq(IVotingEscrow(VE).getLockDelegatee(SAFE_TOKEN_ID), CONDUIT);
    }

    /* ----------------------------------------------------------------------------------------------------------
                                                       vote
    ---------------------------------------------------------------------------------------------------------- */

    function test_vote_throughModule() public {
        _fork(BLOCK);
        _wire();
        assertTrue(ISafe(SAFE).isModuleEnabled(address(module)));

        vm.prank(keeper);
        module.vote(pools, weights);

        assertEq(IVoter(VOTER).lastVoted(CONDUIT), block.timestamp);
        assertEq(IVoter(VOTER).poolVoteLength(CONDUIT), 3);
        uint256 total;
        for (uint256 i; i < 3; ++i) {
            assertEq(IVoter(VOTER).poolVote(CONDUIT, i), pools[i]);
            uint256 expected = (weights[i] * CONDUIT_POWER) / 100;
            assertEq(IVoter(VOTER).votes(CONDUIT, pools[i]), expected);
            total += expected;
        }
        assertLe(total, CONDUIT_POWER);
        assertGe(total, CONDUIT_POWER - 3);
    }

    function test_vote_replaysSeptember9() public {
        _fork(REPLAY_BLOCK);
        _wire();
        assertEq(IVoter(VOTER)._epochTimestamp(), REPLAY_EPOCH_START);
        assertEq(IVotingEscrow(VE).getPastVotes(CONDUIT, REPLAY_EPOCH_START), REPLAY_POWER);

        bytes memory keeperCalldata = abi.encodeCall(IKlimaVeTokenConduit.vote, (pools, weights));
        assertEq(
            keccak256(keeperCalldata),
            keccak256(
                hex"6f816a20" hex"0000000000000000000000000000000000000000000000000000000000000040"
                hex"00000000000000000000000000000000000000000000000000000000000000c0"
                hex"0000000000000000000000000000000000000000000000000000000000000003"
                hex"0000000000000000000000007796fc53b75960a9762ba267c19f5da9868b7853"
                hex"0000000000000000000000009849e92f29a9d3b89fe09694746e7acf52bbc37d"
                hex"00000000000000000000000051f0b932855986b0e621c9d4db6eee1f4644d3d2"
                hex"0000000000000000000000000000000000000000000000000000000000000003"
                hex"000000000000000000000000000000000000000000000000000000000000004a"
                hex"0000000000000000000000000000000000000000000000000000000000000011"
                hex"0000000000000000000000000000000000000000000000000000000000000009"
            ),
            "not the calldata the keeper sent"
        );

        for (uint256 i; i < 3; ++i) {
            vm.expectEmit(VOTER);
            emit Voted(CONDUIT, replayVotes[i]);
        }
        vm.prank(keeper);
        module.vote(pools, weights);

        assertEq(IVoter(VOTER).poolVoteLength(CONDUIT), 3);
        for (uint256 i; i < 3; ++i) {
            assertEq(IVoter(VOTER).poolVote(CONDUIT, i), pools[i]);
            assertEq(IVoter(VOTER).votes(CONDUIT, pools[i]), replayVotes[i]);
        }
    }

    event Voted(address indexed voter, uint256 weight);

    function test_vote_revertsForNonKeeper() public {
        _fork(BLOCK);
        _wire();
        address[3] memory callers = [HYDREX_KEEPER, HYDREX_ADMIN, SAFE];
        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(KlimaConduitExecutor.NotKeeper.selector);
            vm.prank(callers[i]);
            module.vote(pools, weights);
        }
        assertEq(IVoter(VOTER).lastVoted(CONDUIT), 1_788_955_305);
    }

    function test_vote_revertsBeforeHydrexGrant() public {
        _fork(BLOCK);
        _enable();
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", SAFE, EXECUTOR_ROLE)
        );
        vm.prank(keeper);
        module.vote(pools, weights);
        assertEq(IVoter(VOTER).lastVoted(CONDUIT), 1_788_955_305);
    }

    function test_vote_revertsBeforeSafeEnablesModule() public {
        _fork(BLOCK);
        _grant();
        vm.expectRevert(bytes("GS104"));
        vm.prank(keeper);
        module.vote(pools, weights);
    }

    function test_vote_bubblesVoterRevert() public {
        _fork(BLOCK);
        _wire();
        address[] memory onePool = new address[](1);
        onePool[0] = pools[0];
        vm.expectRevert(bytes("Pools/weights length mismatch"));
        vm.prank(keeper);
        module.vote(onePool, weights);
    }

    /* ----------------------------------------------------------------------------------------------------------
                                              claimSwapAndDistribute
    ---------------------------------------------------------------------------------------------------------- */

    function test_claim_throughModule() public {
        _fork(BLOCK);
        _wire();

        vm.recordLogs();
        _claim(keeper, SAFE_TOKEN_ID);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 completed = keccak256(
            "ClaimSwapAndDistributeCompleted(uint256,address,address,address[],uint256[],address[],uint256[],uint256[])"
        );
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == CONDUIT && logs[i].topics[0] == completed) {
                seen = true;
                assertEq(uint256(logs[i].topics[1]), SAFE_TOKEN_ID);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), SAFE);
            }
        }
        assertTrue(seen, "conduit did not complete the claim");
    }

    function test_claim_bubblesConduitRevert() public {
        _fork(BLOCK);
        _wire();
        uint256 missing = type(uint256).max;
        bytes memory call = abi.encodeCall(
            IKlimaVeTokenConduit.claimSwapAndDistribute,
            (missing, new address[](0), new bytes[](0), new address[](0), new address[](0), new address[](0), 0, 0)
        );
        vm.prank(SAFE);
        (bool ok, bytes memory expected) = CONDUIT.call(call);
        assertFalse(ok);
        assertTrue(expected.length != 0);

        vm.expectRevert(expected);
        _claim(keeper, missing);
    }

    function test_claim_revertsForNonKeeper() public {
        _fork(BLOCK);
        _wire();
        vm.expectRevert(KlimaConduitExecutor.NotKeeper.selector);
        _claim(HYDREX_KEEPER, SAFE_TOKEN_ID);
    }

    function test_claim_revertsBeforeHydrexGrant() public {
        _fork(BLOCK);
        _enable();
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", SAFE, EXECUTOR_ROLE)
        );
        _claim(keeper, SAFE_TOKEN_ID);
    }
}
