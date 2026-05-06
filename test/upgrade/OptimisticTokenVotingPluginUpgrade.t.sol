// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "../base/AragonTest.sol";
import {DaoBuilder} from "../helpers/DaoBuilder.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {GovernanceERC20Mock} from "../mocks/GovernanceERC20Mock.sol";
import {ITaikoL1} from "../../src/adapted-dependencies/ITaikoL1.sol";

contract OptimisticTokenVotingPluginUpgradeTest is AragonTest {
    DaoBuilder builder;

    DAO dao;
    OptimisticTokenVotingPlugin optimisticPlugin;
    GovernanceERC20Mock votingToken;
    ITaikoL1 taikoL1;

    event L2VetoReceiverUpdated(address oldReceiver, address newReceiver);
    event L2VetoesReceived(uint256 indexed proposalId, uint256 l2VetoTally);
    event Upgraded(address indexed implementation);

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, optimisticPlugin,,, votingToken,,, taikoL1) = builder.build();
    }

    function _grantUpgradePermission() internal {
        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.UPGRADE_PLUGIN_PERMISSION_ID());
    }

    function _upgradePlugin() internal returns (address newImpl) {
        _grantUpgradePermission();
        newImpl = address(new OptimisticTokenVotingPlugin());
        optimisticPlugin.upgradeTo(newImpl);
    }

    function _createProposal() internal returns (uint256 proposalId) {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);
    }

    function _createProposalWithL2() internal returns (uint256 proposalId) {
        (dao, optimisticPlugin,,, votingToken,,,) =
            builder.withTokenHolder(alice, 10 ether).withTokenHolder(taikoERC20Vault, 10 ether).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);
    }

    // =========================================================================
    // Storage Preservation
    // =========================================================================

    function test_UpgradePreservesGovernanceSettings() public {
        // Read settings before upgrade
        (
            uint32 minVetoRatioBefore,
            uint32 minDurationBefore,
            uint32 timelockPeriodBefore,
            uint32 l2InactivityPeriodBefore,
            uint32 l2AggregationGracePeriodBefore,
            bool skipL2Before
        ) = optimisticPlugin.governanceSettings();

        _upgradePlugin();

        (
            uint32 minVetoRatioAfter,
            uint32 minDurationAfter,
            uint32 timelockPeriodAfter,
            uint32 l2InactivityPeriodAfter,
            uint32 l2AggregationGracePeriodAfter,
            bool skipL2After
        ) = optimisticPlugin.governanceSettings();

        assertEq(minVetoRatioAfter, minVetoRatioBefore, "minVetoRatio changed");
        assertEq(minDurationAfter, minDurationBefore, "minDuration changed");
        assertEq(timelockPeriodAfter, timelockPeriodBefore, "timelockPeriod changed");
        assertEq(l2InactivityPeriodAfter, l2InactivityPeriodBefore, "l2InactivityPeriod changed");
        assertEq(l2AggregationGracePeriodAfter, l2AggregationGracePeriodBefore, "l2AggregationGracePeriod changed");
        assertEq(skipL2After, skipL2Before, "skipL2 changed");
    }

    function test_UpgradePreservesTokenAndAddresses() public {
        address tokenBefore = address(optimisticPlugin.votingToken());
        address taikoL1Before = address(optimisticPlugin.taikoL1());
        address vaultBefore = optimisticPlugin.taikoERC20Vault();

        _upgradePlugin();

        assertEq(address(optimisticPlugin.votingToken()), tokenBefore, "votingToken changed");
        assertEq(address(optimisticPlugin.taikoL1()), taikoL1Before, "taikoL1 changed");
        assertEq(optimisticPlugin.taikoERC20Vault(), vaultBefore, "taikoERC20Vault changed");
    }

    function test_UpgradePreservesProposalData() public {
        uint256 proposalId = _createProposal();

        // Cast a veto
        optimisticPlugin.veto(proposalId);

        // Read proposal state before upgrade
        (
            bool openBefore,
            bool executedBefore,
            OptimisticTokenVotingPlugin.ProposalParameters memory paramsBefore,
            uint256 vetoTallyBefore,
            bytes memory metadataBefore,
            ,
        ) = optimisticPlugin.getProposal(proposalId);

        _upgradePlugin();

        (
            bool openAfter,
            bool executedAfter,
            OptimisticTokenVotingPlugin.ProposalParameters memory paramsAfter,
            uint256 vetoTallyAfter,
            bytes memory metadataAfter,
            ,
        ) = optimisticPlugin.getProposal(proposalId);

        assertEq(openAfter, openBefore, "open changed");
        assertEq(executedAfter, executedBefore, "executed changed");
        assertEq(vetoTallyAfter, vetoTallyBefore, "vetoTally changed");
        assertEq(keccak256(metadataAfter), keccak256(metadataBefore), "metadata changed");
        assertEq(paramsAfter.snapshotTimestamp, paramsBefore.snapshotTimestamp, "snapshotTimestamp changed");
        assertEq(paramsAfter.vetoStartDate, paramsBefore.vetoStartDate, "vetoStartDate changed");
        assertEq(paramsAfter.vetoEndDate, paramsBefore.vetoEndDate, "vetoEndDate changed");
        assertEq(paramsAfter.minVetoRatio, paramsBefore.minVetoRatio, "minVetoRatio changed");
    }

    function test_UpgradePreservesProposalCount() public {
        _createProposal();
        _createProposal();

        uint256 countBefore = optimisticPlugin.proposalCount();
        assertEq(countBefore, 2, "Should have 2 proposals");

        _upgradePlugin();

        assertEq(optimisticPlugin.proposalCount(), countBefore, "proposalCount changed");
    }

    function test_UpgradePreservesL2VetoReceiver() public {
        // Set L2 receiver before upgrade
        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.UPDATE_L2_VETO_RECEIVER_PERMISSION_ID());
        address receiver = address(0xBEEF);
        optimisticPlugin.setL2VetoReceiver(receiver);

        _upgradePlugin();

        assertEq(optimisticPlugin.l2VetoReceiver(), receiver, "l2VetoReceiver changed");
    }

    // =========================================================================
    // L2 Features After Upgrade
    // =========================================================================

    function test_SetL2VetoReceiverWorksAfterUpgrade() public {
        _upgradePlugin();

        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.UPDATE_L2_VETO_RECEIVER_PERMISSION_ID());

        address receiver = address(0xBEEF);
        vm.expectEmit();
        emit L2VetoReceiverUpdated(address(0), receiver);
        optimisticPlugin.setL2VetoReceiver(receiver);

        assertEq(optimisticPlugin.l2VetoReceiver(), receiver);
    }

    function test_ReceiveL2VetoesWorksAfterUpgrade() public {
        uint256 proposalId = _createProposalWithL2();

        _upgradePlugin();

        // Set test contract as L2 receiver
        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.UPDATE_L2_VETO_RECEIVER_PERMISSION_ID());
        optimisticPlugin.setL2VetoReceiver(address(this));

        // Receive L2 vetoes
        vm.stopPrank();
        vm.expectEmit();
        emit L2VetoesReceived(proposalId, 3 ether);
        optimisticPlugin.receiveL2Vetoes(proposalId, 3 ether);

        // Verify tally updated
        (,,, uint256 vetoTally,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(vetoTally, 3 ether, "L2 vetoes not reflected in tally");
    }

    // =========================================================================
    // Old Proposals Remain Functional
    // =========================================================================

    function test_OldProposalsCanBeVetoedAfterUpgrade() public {
        uint256 proposalId = _createProposal();

        _upgradePlugin();

        assertTrue(optimisticPlugin.canVeto(proposalId, alice), "Should be able to veto after upgrade");
        optimisticPlugin.veto(proposalId);
        assertTrue(optimisticPlugin.hasVetoed(proposalId, alice), "Veto should be recorded");
    }

    function test_OldProposalsCanBeExecutedAfterUpgrade() public {
        uint256 proposalId = _createProposal();

        _upgradePlugin();

        // Wait for end + timelock
        (,, uint32 timelockPeriod,,,) = optimisticPlugin.governanceSettings();
        vm.warp(block.timestamp + 4 days + builder.l2AggregationGracePeriod() + timelockPeriod);

        assertTrue(optimisticPlugin.canExecute(proposalId), "Should be executable after upgrade");
        optimisticPlugin.execute(proposalId);

        (, bool executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertTrue(executed, "Should be marked as executed");
    }

    // =========================================================================
    // New Proposals After Upgrade
    // =========================================================================

    function test_NewProposalsHaveSnapshotTimestampInId() public {
        _upgradePlugin();

        uint256 proposalId = _createProposal();

        (uint64 counter, uint64 startDate, uint64 endDate, uint64 snapshotTimestamp) =
            optimisticPlugin.parseProposalId(proposalId);

        assertEq(
            snapshotTimestamp,
            uint64(block.timestamp - optimisticPlugin.SNAPSHOT_OFFSET()),
            "snapshotTimestamp should be block.timestamp - SNAPSHOT_OFFSET"
        );
        assertEq(startDate, uint64(block.timestamp), "startDate should be block.timestamp");
        assertEq(endDate, uint64(block.timestamp + 4 days), "endDate should be startDate + duration");
        assertEq(counter, 0, "counter should be 0 for first proposal");
    }

    function test_NewProposalsSnapshotTimestampMatchesStored() public {
        _upgradePlugin();

        uint256 proposalId = _createProposal();

        (,,, uint64 extractedSnapshot) = optimisticPlugin.parseProposalId(proposalId);
        (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(extractedSnapshot, params.snapshotTimestamp, "Snapshot in ID should match stored snapshot");
    }
}
