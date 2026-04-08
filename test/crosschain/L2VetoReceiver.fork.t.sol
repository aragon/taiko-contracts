// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Vm, Test} from "forge-std/Test.sol";
import {E2ETestBase} from "../base/E2ETestBase.sol";
import {TaikoBridgeMock} from "../mocks/TaikoBridgeMock.sol";
import {GovernanceERC20Mock} from "../mocks/GovernanceERC20Mock.sol";
import {L2VetoAggregator} from "../../src/crosschain/L2VetoAggregator.sol";
import {L2VetoReceiver} from "../../src/crosschain/L2VetoReceiver.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {IBridge} from "../../src/interfaces/IBridge.sol";
import {TaikoHelper} from "../helpers/TaikoHelper.sol";

/// @notice Local E2E test — full aggregator->dispatch->relay->receiver->plugin path
/// @dev No RPC needed. Uses TaikoBridgeMock for both "L2" and "L1" bridges.
///      Uses uint64(block.chainid) as the chain ID for both sides so bridge context matches.
contract CrosschainVetoLocalTest is E2ETestBase {
    TaikoBridgeMock l1Bridge;
    TaikoBridgeMock l2Bridge;
    GovernanceERC20Mock l2VotingToken;
    L2VetoAggregator aggregator;
    TaikoHelper taikoHelper;

    function setUp() public {
        l1Bridge = new TaikoBridgeMock();
        l2Bridge = new TaikoBridgeMock();

        _install();
        _deployL2VetoReceiver(address(l1Bridge), uint64(block.chainid));
        _initUpgradeFactory();

        // L2 voting token — separate from L1 votingToken
        l2VotingToken = new GovernanceERC20Mock(address(dao));
        l2VotingToken.mintAndDelegate(bob, 3 ether);

        // L2VetoAggregator — uses l2Bridge, targets l2VetoReceiver on "L1"
        aggregator = new L2VetoAggregator(
            address(l2Bridge),
            uint64(block.chainid), // destChainId = same chain in local test
            address(l2VotingToken),
            address(l2VetoReceiver)
        );

        // Receiver must trust the aggregator's address (bridge sets from = msg.sender = aggregator)
        trustedL2Aggregator = address(aggregator);

        taikoHelper = new TaikoHelper();
    }

    function test_LocalE2E_L2VetosReachPlugin() public {
        // Phase 1: upgrade + finalize (sets trustedL2Aggregator = address(aggregator))
        _runUpgrade();
        _runFinalize();

        // Phase 2: create proposal with L2 enabled
        (uint256 proposalId, uint64 vetoEndDate) = _mintVaultTokensAndCreateProposal();

        // Verify L2 is enabled
        (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        assertFalse(params.unavailableL2, "L2 should be available");

        // Phase 3: bob vetoes on the aggregator (within veto period)
        vm.prank(bob);
        aggregator.veto(proposalId);

        uint256 expectedVotingPower = l2VotingToken.getVotes(bob);
        assertEq(aggregator.getVetoTally(proposalId), expectedVotingPower, "Aggregator tally mismatch");

        // Phase 4: dispatch before vetoEndDate, then warp into grace period
        vm.recordLogs();
        aggregator.dispatch(proposalId);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        vm.warp(vetoEndDate + 1);

        // Phase 5: extract message from logs and relay to receiver via TaikoHelper
        IBridge.Message memory message;
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == taikoHelper.MESSAGE_SENT_SELECTOR()) {
                message = taikoHelper.extractMessage(logs[i]);
                found = true;
                break;
            }
        }
        assertTrue(found, "MessageSent event not found");

        taikoHelper.relayMessageLocal(address(l1Bridge), message);

        // Phase 6: assert receiver state
        assertEq(l2VetoReceiver.getL2VetoTally(proposalId), expectedVotingPower, "Receiver tally mismatch");
        assertTrue(l2VetoReceiver.hasReceivedL2Vetoes(proposalId), "Receiver should mark vetoes received");

        // Phase 7: assert plugin state
        (,,, uint256 pluginVetoTally,,,) = plugin.getProposal(proposalId);
        assertEq(pluginVetoTally, expectedVotingPower, "Plugin vetoTally should reflect L2 vetoes");
    }
}

/// @notice Fork E2E test — deploys on real L1/L2 forks with real Taiko bridges
/// @dev Requires environment variables:
///      - L1_RPC_URL, L2_RPC_URL: fork endpoints
///      - L1_TAIKO_BRIDGE, L2_TAIKO_BRIDGE: bridge addresses
///      - L2_CHAIN_ID: L2 chain ID
///      Optional:
///      - FORK_USE_REAL_TOKEN=true: use real on-chain L2 token instead of mock
///      - L2_VOTING_TOKEN: real bridged token address (required if FORK_USE_REAL_TOKEN)
///      - L2_VOTER_ADDRESS: address with delegated voting power (required if FORK_USE_REAL_TOKEN)
contract CrosschainVetoForkTest is E2ETestBase {
    uint256 l1ForkId;
    uint256 l2ForkId;

    address l1BridgeAddr;
    address l2BridgeAddr;
    uint64 l2ChainId;

    L2VetoAggregator aggregator;
    TaikoHelper taikoHelper;

    address l2VotingTokenAddr;
    address voter;
    bool useRealToken;
    bool forksAvailable;

    uint256 l2MintTimestamp;

    modifier skipIfNoForks() {
        if (!forksAvailable) return;
        _;
    }

    function setUp() public {
        string memory l1Rpc = vm.envOr("L1_RPC_URL", string(""));
        string memory l2Rpc = vm.envOr("L2_RPC_URL", string(""));

        if (bytes(l1Rpc).length == 0 || bytes(l2Rpc).length == 0) {
            forksAvailable = false;
            return;
        }

        forksAvailable = true;

        l1ForkId = vm.createFork(l1Rpc);
        l2ForkId = vm.createFork(l2Rpc);

        l1BridgeAddr = vm.envAddress("L1_TAIKO_BRIDGE");
        l2BridgeAddr = vm.envAddress("L2_TAIKO_BRIDGE");
        l2ChainId = uint64(vm.envUint("L2_CHAIN_ID"));
        useRealToken = vm.envOr("FORK_USE_REAL_TOKEN", false);

        // --- L2 fork: set up voting token ---
        vm.selectFork(l2ForkId);

        if (useRealToken) {
            l2VotingTokenAddr = vm.envAddress("L2_VOTING_TOKEN");
            voter = vm.envAddress("L2_VOTER_ADDRESS");
        } else {
            voter = bob;
            GovernanceERC20Mock l2Token = new GovernanceERC20Mock(address(1));
            l2Token.mintAndDelegate(voter, 3 ether);
            l2VotingTokenAddr = address(l2Token);
        }

        l2MintTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // --- L1 fork: full factory deployment ---
        vm.selectFork(l1ForkId);

        // Ensure L1 is ahead of L2 mint time so proposal snapshot captures L2 votes
        if (block.timestamp <= l2MintTimestamp + 1) {
            vm.warp(l2MintTimestamp + 2);
            vm.roll(block.number + 1);
        }

        _install();
        _deployL2VetoReceiver(l1BridgeAddr, l2ChainId);
        _initUpgradeFactory();

        // --- L2 fork: deploy aggregator (needs l2VetoReceiver address from L1) ---
        vm.selectFork(l1ForkId);
        uint64 l1ChainId = uint64(block.chainid);
        vm.selectFork(l2ForkId);

        aggregator = new L2VetoAggregator(
            l2BridgeAddr,
            l1ChainId,
            l2VotingTokenAddr,
            address(l2VetoReceiver)
        );

        trustedL2Aggregator = address(aggregator);

        taikoHelper = new TaikoHelper();
    }

    function test_forkSetup() public skipIfNoForks {
        vm.selectFork(l1ForkId);
        assertEq(l2VetoReceiver.bridge(), l1BridgeAddr);
        assertEq(l2VetoReceiver.l2ChainId(), l2ChainId);
    }

    function test_l1BridgeExists() public skipIfNoForks {
        vm.selectFork(l1ForkId);
        assertGt(l1BridgeAddr.code.length, 0, "L1 Bridge should have code");
    }

    function test_l2BridgeExists() public skipIfNoForks {
        vm.selectFork(l2ForkId);
        assertGt(l2BridgeAddr.code.length, 0, "L2 Bridge should have code");
    }

    function test_ForkE2E_L2VetosReachPlugin() public skipIfNoForks {
        // Phase 1: L1 — upgrade + finalize + create proposal
        vm.selectFork(l1ForkId);
        _runUpgrade();
        _runFinalize();

        (uint256 proposalId, uint64 vetoEndDate) = _mintVaultTokensAndCreateProposal();

        (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        assertFalse(params.unavailableL2, "L2 should be available");
        uint64 vetoStartDate = params.vetoStartDate;

        // Phase 2: L2 — warp to veto period, cast veto, dispatch
        vm.selectFork(l2ForkId);

        // Align L2 time to be within the proposal's veto period
        vm.warp(vetoStartDate + 1);
        vm.roll(block.number + 1);

        vm.prank(voter);
        aggregator.veto(proposalId);

        // Warp into grace period for dispatch + relay
        vm.warp(vetoEndDate + 1);

        vm.recordLogs();
        aggregator.dispatch(proposalId);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Phase 3: relay L2->L1 via TaikoHelper
        taikoHelper.relay(l2BridgeAddr, l1BridgeAddr, l1ForkId, logs);

        // Phase 4: L1 — assert receiver + plugin state
        vm.selectFork(l1ForkId);

        // Warp L1 to match L2's timestamp (grace period)
        vm.warp(vetoEndDate + 1);

        assertTrue(l2VetoReceiver.hasReceivedL2Vetoes(proposalId), "Receiver should mark vetoes received");
        assertGt(l2VetoReceiver.getL2VetoTally(proposalId), 0, "Receiver should have non-zero tally");

        (,,, uint256 pluginVetoTally,,,) = plugin.getProposal(proposalId);
        assertGt(pluginVetoTally, 0, "Plugin vetoTally should reflect L2 vetoes");
    }
}
