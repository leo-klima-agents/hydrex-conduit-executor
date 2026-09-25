// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {KlimaVeTokenConduitExecutor} from "../src/KlimaVeTokenConduitExecutor.sol";
import {IKlimaVeTokenConduit} from "../src/interfaces/IKlimaVeTokenConduit.sol";
import {MockConduit} from "./mocks/MockConduit.sol";
import {FailingSafe, MockSafe} from "./mocks/MockSafe.sol";
import {ModuleTestBase} from "./utils/ModuleTestBase.sol";

contract KlimaVeTokenConduitExecutorTest is ModuleTestBase {
    address internal keeper;
    address internal stranger;

    MockSafe internal safe;
    MockConduit internal conduit;

    address[] internal pools;
    uint256[] internal weights;

    function setUp() public {
        keeper = makeAddr("keeper");
        stranger = makeAddr("stranger");
        safe = new MockSafe();
        conduit = new MockConduit();
        module = new KlimaVeTokenConduitExecutor(address(safe), address(conduit), keeper);

        conduit.grantExecutor(address(safe));
        safe.enableModule(address(module));

        pools.push(makeAddr("pool0"));
        pools.push(makeAddr("pool1"));
        weights.push(74);
        weights.push(26);
    }

    function test_constructor_storesImmutables() public view {
        assertEq(module.SAFE(), address(safe));
        assertEq(module.CONDUIT(), address(conduit));
        assertEq(module.KEEPER(), keeper);
    }

    function test_constructor_revertsZeroSafe() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.ZeroAddress.selector);
        new KlimaVeTokenConduitExecutor(address(0), address(conduit), keeper);
    }

    function test_constructor_revertsZeroConduit() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.ZeroAddress.selector);
        new KlimaVeTokenConduitExecutor(address(safe), address(0), keeper);
    }

    function test_constructor_revertsZeroKeeper() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.ZeroAddress.selector);
        new KlimaVeTokenConduitExecutor(address(safe), address(conduit), address(0));
    }

    function test_constructor_revertsSafeWithoutCode() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.NotAContract.selector);
        new KlimaVeTokenConduitExecutor(makeAddr("eoa"), address(conduit), keeper);
    }

    function test_constructor_revertsConduitWithoutCode() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.NotAContract.selector);
        new KlimaVeTokenConduitExecutor(address(safe), makeAddr("eoa"), keeper);
    }

    function test_constructor_zeroCheckedBeforeCode() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.ZeroAddress.selector);
        new KlimaVeTokenConduitExecutor(address(0), makeAddr("eoa"), keeper);
    }

    function test_constructor_keeperMayBeAnyNonZeroAddress() public {
        KlimaVeTokenConduitExecutor m =
            new KlimaVeTokenConduitExecutor(address(safe), address(conduit), address(conduit));
        assertEq(m.KEEPER(), address(conduit));
    }

    function testFuzz_constructor(address s, address c, address k) public {
        if (s == address(0) || c == address(0) || k == address(0)) {
            vm.expectRevert(KlimaVeTokenConduitExecutor.ZeroAddress.selector);
            new KlimaVeTokenConduitExecutor(s, c, k);
            return;
        }
        if (s.code.length == 0 || c.code.length == 0) {
            vm.expectRevert(KlimaVeTokenConduitExecutor.NotAContract.selector);
            new KlimaVeTokenConduitExecutor(s, c, k);
            return;
        }
        KlimaVeTokenConduitExecutor m = new KlimaVeTokenConduitExecutor(s, c, k);
        assertEq(m.SAFE(), s);
        assertEq(m.CONDUIT(), c);
        assertEq(m.KEEPER(), k);
    }

    function testFuzz_constructor_anyContracts(bytes32 saltA, bytes32 saltB, address k) public {
        vm.assume(k != address(0));
        MockSafe s = new MockSafe{salt: saltA}();
        MockConduit c = new MockConduit{salt: saltB}();
        KlimaVeTokenConduitExecutor m = new KlimaVeTokenConduitExecutor(address(s), address(c), k);
        assertEq(m.SAFE(), address(s));
        assertEq(m.CONDUIT(), address(c));
        assertEq(m.KEEPER(), k);
    }

    function test_vote_keeperReachesConduitThroughSafe() public {
        vm.expectEmit(address(safe));
        emit MockSafe.ExecutionFromModuleSuccess(address(module));
        vm.prank(keeper);
        module.vote(pools, weights);

        assertEq(conduit.voteCalls(), 1);
        assertEq(conduit.lastSender(), address(safe));
        assertEq(conduit.lastCalldata(), abi.encodeCall(IKlimaVeTokenConduit.vote, (pools, weights)));
        assertEq(conduit.lastValue(), 0);

        assertEq(safe.execCalls(), 1);
        assertEq(safe.lastTo(), address(conduit));
        assertEq(safe.lastValue(), 0);
        assertEq(safe.lastOperation(), 0);
        assertEq(safe.lastData(), abi.encodeCall(IKlimaVeTokenConduit.vote, (pools, weights)));
    }

    function testFuzz_vote_forwardsExactCalldata(address[] memory p, uint256 seed) public {
        uint256[] memory w = new uint256[](p.length);
        for (uint256 i; i < w.length; ++i) {
            w[i] = uint256(keccak256(abi.encode(seed, i)));
        }
        vm.prank(keeper);
        module.vote(p, w);

        assertEq(conduit.lastCalldata(), abi.encodeCall(IKlimaVeTokenConduit.vote, (p, w)));
        assertEq(conduit.lastSender(), address(safe));
        assertEq(safe.lastTo(), address(conduit));
        assertEq(safe.lastOperation(), 0);
    }

    function test_vote_emptyArraysReachConduit() public {
        vm.prank(keeper);
        module.vote(new address[](0), new uint256[](0));
        assertEq(conduit.voteCalls(), 1);
    }

    function test_vote_revertsForStranger() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.NotKeeper.selector);
        vm.prank(stranger);
        module.vote(pools, weights);
        assertEq(conduit.voteCalls(), 0);
        assertEq(safe.execCalls(), 0);
    }

    function test_vote_revertsForSafeItself() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.NotKeeper.selector);
        vm.prank(address(safe));
        module.vote(pools, weights);
    }

    function test_vote_revertsForConduit() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.NotKeeper.selector);
        vm.prank(address(conduit));
        module.vote(pools, weights);
    }

    function testFuzz_vote_revertsForAnyNonKeeper(address caller) public {
        vm.assume(caller != keeper);
        vm.expectRevert(KlimaVeTokenConduitExecutor.NotKeeper.selector);
        vm.prank(caller);
        module.vote(pools, weights);
        assertEq(safe.execCalls(), 0);
    }

    function test_vote_bubblesConduitStringRevert() public {
        uint256[] memory oneWeight = new uint256[](1);
        vm.expectRevert(bytes("Pools/weights length mismatch"));
        vm.prank(keeper);
        module.vote(pools, oneWeight);
    }

    function test_vote_bubblesConduitRoleRevert() public {
        conduit.revokeExecutor(address(safe));
        assertFalse(conduit.hasRole(conduit.EXECUTOR_ROLE(), address(safe)));
        vm.expectRevert(
            abi.encodeWithSelector(
                MockConduit.AccessControlUnauthorizedAccount.selector, address(safe), conduit.EXECUTOR_ROLE()
            )
        );
        vm.prank(keeper);
        module.vote(pools, weights);
    }

    function test_vote_bubblesConduitCustomError() public {
        conduit.revertWith(abi.encodeWithSelector(MockConduit.Boom.selector, 42));
        vm.expectRevert(abi.encodeWithSelector(MockConduit.Boom.selector, 42));
        vm.prank(keeper);
        module.vote(pools, weights);
    }

    function testFuzz_vote_bubblesArbitraryRevertData(bytes memory data) public {
        vm.assume(data.length != 0);
        conduit.revertWith(data);
        vm.expectRevert(data);
        vm.prank(keeper);
        module.vote(pools, weights);
    }

    function test_vote_emptyConduitRevertBecomesExecutionFailed() public {
        conduit.revertWith("");
        vm.expectRevert(KlimaVeTokenConduitExecutor.ExecutionFailed.selector);
        vm.prank(keeper);
        module.vote(pools, weights);
    }

    function test_vote_safeReturningFalseReverts() public {
        FailingSafe failing = new FailingSafe();
        KlimaVeTokenConduitExecutor m = new KlimaVeTokenConduitExecutor(address(failing), address(conduit), keeper);
        failing.enableModule(address(m));

        vm.expectRevert(KlimaVeTokenConduitExecutor.ExecutionFailed.selector);
        vm.prank(keeper);
        m.vote(pools, weights);
        assertEq(conduit.voteCalls(), 0);
    }

    function test_vote_revertsWhenModuleNotEnabled() public {
        safe.disableModule(address(module));
        vm.expectRevert(bytes("GS104"));
        vm.prank(keeper);
        module.vote(pools, weights);
        assertEq(conduit.voteCalls(), 0);
    }

    function test_claim_keeperReachesConduitThroughSafe() public {
        address[] memory targets = new address[](1);
        targets[0] = makeAddr("kyber");
        bytes[] memory swaps = new bytes[](1);
        swaps[0] = hex"deadbeef";
        address[] memory fees = new address[](2);
        (fees[0], fees[1]) = (makeAddr("fee0"), makeAddr("fee1"));
        address[] memory bribes = new address[](1);
        bribes[0] = makeAddr("bribe0");
        address[] memory claimTokens = new address[](3);
        (claimTokens[0], claimTokens[1], claimTokens[2]) = (makeAddr("t0"), makeAddr("t1"), makeAddr("t2"));

        vm.expectEmit(address(safe));
        emit MockSafe.ExecutionFromModuleSuccess(address(module));
        vm.prank(keeper);
        module.claimSwapAndDistribute(14_247, targets, swaps, fees, bribes, claimTokens, 3, 1e18);

        assertEq(conduit.claimCalls(), 1);
        assertEq(conduit.lastSender(), address(safe));
        assertEq(conduit.lastValue(), 0);
        assertEq(
            conduit.lastCalldata(),
            abi.encodeCall(
                IKlimaVeTokenConduit.claimSwapAndDistribute,
                (14_247, targets, swaps, fees, bribes, claimTokens, 3, 1e18)
            )
        );
        assertEq(safe.lastTo(), address(conduit));
        assertEq(safe.lastValue(), 0);
        assertEq(safe.lastOperation(), 0);
    }

    function testFuzz_claim_forwardsExactCalldata(
        uint256 tokenId,
        address[] memory targets,
        bytes[] memory swaps,
        address[] memory fees,
        address[] memory bribes,
        address[] memory claimTokens,
        uint256 retireTonnes,
        uint256 maxKvcmIn
    ) public {
        vm.prank(keeper);
        module.claimSwapAndDistribute(tokenId, targets, swaps, fees, bribes, claimTokens, retireTonnes, maxKvcmIn);

        assertEq(
            conduit.lastCalldata(),
            abi.encodeCall(
                IKlimaVeTokenConduit.claimSwapAndDistribute,
                (tokenId, targets, swaps, fees, bribes, claimTokens, retireTonnes, maxKvcmIn)
            )
        );
        assertEq(conduit.lastSender(), address(safe));
        assertEq(safe.lastTo(), address(conduit));
        assertEq(safe.lastOperation(), 0);
    }

    function test_claim_revertsForStranger() public {
        vm.expectRevert(KlimaVeTokenConduitExecutor.NotKeeper.selector);
        _claim(stranger, 1);
        assertEq(conduit.claimCalls(), 0);
        assertEq(safe.execCalls(), 0);
    }

    function testFuzz_claim_revertsForAnyNonKeeper(address caller) public {
        vm.assume(caller != keeper);
        vm.expectRevert(KlimaVeTokenConduitExecutor.NotKeeper.selector);
        _claim(caller, 1);
    }

    function test_claim_bubblesConduitRevert() public {
        conduit.revertWith(bytes("Router not approved"));
        vm.expectRevert(bytes("Router not approved"));
        _claim(keeper, 1);
    }

    function test_claim_bubblesConduitRoleRevert() public {
        conduit.revokeExecutor(address(safe));
        assertFalse(conduit.hasRole(conduit.EXECUTOR_ROLE(), address(safe)));
        vm.expectRevert(
            abi.encodeWithSelector(
                MockConduit.AccessControlUnauthorizedAccount.selector, address(safe), conduit.EXECUTOR_ROLE()
            )
        );
        _claim(keeper, 1);
    }

    function test_claim_emptyConduitRevertBecomesExecutionFailed() public {
        conduit.revertWith("");
        vm.expectRevert(KlimaVeTokenConduitExecutor.ExecutionFailed.selector);
        _claim(keeper, 1);
    }

    function test_claim_safeReturningFalseReverts() public {
        FailingSafe failing = new FailingSafe();
        KlimaVeTokenConduitExecutor m = new KlimaVeTokenConduitExecutor(address(failing), address(conduit), keeper);
        failing.enableModule(address(m));

        vm.expectRevert(KlimaVeTokenConduitExecutor.ExecutionFailed.selector);
        vm.prank(keeper);
        m.claimSwapAndDistribute(
            1, new address[](0), new bytes[](0), new address[](0), new address[](0), new address[](0), 0, 0
        );
    }

    function test_claim_revertsWhenModuleNotEnabled() public {
        safe.disableModule(address(module));
        vm.expectRevert(bytes("GS104"));
        _claim(keeper, 1);
    }

    function test_surface_rejectsPlainEth() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool ok,) = address(module).call{value: 1}("");
        assertFalse(ok);
        assertEq(address(module).balance, 0);
    }

    function test_surface_rejectsEthWithCall() public {
        vm.deal(keeper, 1 ether);
        vm.prank(keeper);
        (bool ok,) = address(module).call{value: 1}(abi.encodeCall(KlimaVeTokenConduitExecutor.vote, (pools, weights)));
        assertFalse(ok);
        assertEq(address(module).balance, 0);
        assertEq(conduit.voteCalls(), 0);
    }

    function test_surface_rejectsUnknownSelector() public {
        vm.prank(keeper);
        (bool ok,) = address(module).call(abi.encodeWithSignature("enableModule(address)", stranger));
        assertFalse(ok);
        assertEq(safe.execCalls(), 0);
    }

    function testFuzz_surface_rejectsUnknownSelector(bytes4 selector, bytes memory tail) public {
        vm.assume(selector != KlimaVeTokenConduitExecutor.vote.selector);
        vm.assume(selector != KlimaVeTokenConduitExecutor.claimSwapAndDistribute.selector);
        vm.assume(selector != bytes4(keccak256("SAFE()")));
        vm.assume(selector != bytes4(keccak256("CONDUIT()")));
        vm.assume(selector != bytes4(keccak256("KEEPER()")));
        vm.prank(keeper);
        (bool ok,) = address(module).call(bytes.concat(selector, tail));
        assertFalse(ok);
    }

    function test_surface_noStorageWritten() public {
        vm.record();
        vm.prank(keeper);
        module.vote(pools, weights);
        _claim(keeper, 1);
        conduit.revertWith(abi.encodeWithSelector(MockConduit.Boom.selector, 1));
        vm.expectRevert(abi.encodeWithSelector(MockConduit.Boom.selector, 1));
        vm.prank(keeper);
        module.vote(pools, weights);

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(module));
        assertEq(reads.length, 0, "module read storage");
        assertEq(writes.length, 0, "module wrote storage");
    }

    function test_surface_safeUnchangedByModuleCalls() public {
        vm.prank(keeper);
        module.vote(pools, weights);
        assertEq(address(safe).balance, 0);
        assertTrue(safe.isModuleEnabled(address(module)));
    }
}
