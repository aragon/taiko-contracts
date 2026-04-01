// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {createProxyAndCall} from "../../src/helpers/proxy.sol";
import {GovernanceERC20Mock} from "../mocks/GovernanceERC20Mock.sol";

import {OptimisticTokenVotingPlugin as OptimisticTokenVotingPluginV1} from
    "./reference/v1/OptimisticTokenVotingPlugin.sol";
import {TaikoL1Mock as TaikoL1V1Mock} from "./reference/v1/TaikoL1Mock.sol";

import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {IOptimisticTokenVoting} from "../../src/interfaces/IOptimisticTokenVoting.sol";

contract V1ToV2StorageUpgradeTest is Test {
    address immutable alice = address(0xa11ce);
    address immutable bob = address(0xB0B);
    address immutable taikoBridge = address(0xb61d6e);

    DAO dao;
    GovernanceERC20Mock votingToken;
    TaikoL1V1Mock taikoL1;

    OptimisticTokenVotingPluginV1 v1Plugin;
    address proxyAddr;

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(1 days);
        vm.roll(100);

        // Deploy DAO
        dao = DAO(
            payable(
                createProxyAndCall(
                    address(new DAO()), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        // Deploy token and mint (before warp so checkpoints are in the past)
        votingToken = new GovernanceERC20Mock(address(dao));
        votingToken.mintAndDelegate(alice, 10 ether);
        votingToken.mintAndDelegate(bob, 5 ether);

        // Advance time so getPastVotes can see the minted tokens
        vm.warp(2 days);
        vm.roll(200);

        // Deploy TaikoL1 V1 mock
        taikoL1 = new TaikoL1V1Mock();

        // Deploy V1 implementation and proxy
        OptimisticTokenVotingPluginV1 v1Impl = new OptimisticTokenVotingPluginV1();

        OptimisticTokenVotingPluginV1.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPluginV1
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 4 days,
            timelockPeriod: 7 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 1 days,
            skipL2: true
        });

        proxyAddr = createProxyAndCall(
            address(v1Impl),
            abi.encodeCall(
                OptimisticTokenVotingPluginV1.initialize,
                (dao, settings, votingToken, address(taikoL1), taikoBridge)
            )
        );
        v1Plugin = OptimisticTokenVotingPluginV1(proxyAddr);

        // Grant permissions
        vm.stopPrank();
        dao.grant(address(v1Plugin), alice, v1Plugin.PROPOSER_PERMISSION_ID());
        dao.grant(address(v1Plugin), address(dao), keccak256("UPGRADE_PLUGIN_PERMISSION"));
        dao.grant(address(v1Plugin), alice, keccak256("UPGRADE_PLUGIN_PERMISSION"));
        dao.grant(address(dao), address(v1Plugin), keccak256("EXECUTE_PERMISSION"));
        vm.startPrank(alice);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _createV1Proposal() internal returns (uint256) {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        return v1Plugin.createProposal("ipfs://metadata", actions, 0, 4 days);
    }

    function _upgradeToV2() internal returns (OptimisticTokenVotingPlugin) {
        OptimisticTokenVotingPlugin v2Impl = new OptimisticTokenVotingPlugin();
        v1Plugin.upgradeTo(address(v2Impl));
        return OptimisticTokenVotingPlugin(proxyAddr);
    }

    // =========================================================================
    // Storage: top-level variables
    // =========================================================================

    function test_UpgradeV1ToV2_PreservesVotingToken() public {
        address tokenBefore = address(v1Plugin.votingToken());

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        assertEq(address(v2.votingToken()), tokenBefore, "votingToken changed");
    }

    function test_UpgradeV1ToV2_PreservesTaikoBridgeAsTaikoERC20Vault() public {
        // V1 stored address in slot "taikoBridge", V2 reads same slot as "taikoERC20Vault"
        address bridgeBefore = v1Plugin.taikoBridge();

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        assertEq(v2.taikoERC20Vault(), bridgeBefore, "taikoBridge/taikoERC20Vault slot changed");
    }

    function test_UpgradeV1ToV2_PreservesGovernanceSettings() public {
        (
            uint32 minVetoRatioBefore,
            uint32 minDurationBefore,
            uint32 timelockPeriodBefore,
            uint32 l2InactivityPeriodBefore,
            uint32 l2AggregationGracePeriodBefore,
            bool skipL2Before
        ) = v1Plugin.governanceSettings();

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        (
            uint32 minVetoRatioAfter,
            uint32 minDurationAfter,
            uint32 timelockPeriodAfter,
            uint32 l2InactivityPeriodAfter,
            uint32 l2AggregationGracePeriodAfter,
            bool skipL2After
        ) = v2.governanceSettings();

        assertEq(minVetoRatioAfter, minVetoRatioBefore, "minVetoRatio changed");
        assertEq(minDurationAfter, minDurationBefore, "minDuration changed");
        assertEq(timelockPeriodAfter, timelockPeriodBefore, "timelockPeriod changed");
        assertEq(l2InactivityPeriodAfter, l2InactivityPeriodBefore, "l2InactivityPeriod changed");
        assertEq(l2AggregationGracePeriodAfter, l2AggregationGracePeriodBefore, "l2AggregationGracePeriod changed");
        assertEq(skipL2After, skipL2Before, "skipL2 changed");
    }

    function test_UpgradeV1ToV2_L2VetoReceiverStartsAsZero() public {
        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        assertEq(v2.l2VetoReceiver(), address(0), "l2VetoReceiver should be zero (from gap)");
    }

    // =========================================================================
    // Storage: ProposalParameters struct compatibility
    // =========================================================================

    function test_UpgradeV1ToV2_PreservesProposalParameters() public {
        uint256 proposalId = _createV1Proposal();

        // Read V1 proposal parameters
        (,, OptimisticTokenVotingPluginV1.ProposalParameters memory v1Params,,,,) = v1Plugin.getProposal(proposalId);

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        // Read same proposal through V2
        (,, IOptimisticTokenVoting.ProposalParameters memory v2Params,,,,) = v2.getProposal(proposalId);

        // The 4 original fields must be identical
        assertEq(v2Params.vetoEndDate, v1Params.vetoEndDate, "vetoEndDate changed");
        assertEq(v2Params.snapshotTimestamp, v1Params.snapshotTimestamp, "snapshotTimestamp changed");
        assertEq(v2Params.minVetoRatio, v1Params.minVetoRatio, "minVetoRatio changed");
        assertEq(v2Params.unavailableL2, v1Params.unavailableL2, "unavailableL2 changed");
    }

    function test_UpgradeV1ToV2_OldProposalVetoStartDateIsZero() public {
        uint256 proposalId = _createV1Proposal();

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        (,, IOptimisticTokenVoting.ProposalParameters memory v2Params,,,,) = v2.getProposal(proposalId);

        // V1 never wrote vetoStartDate — those bytes were zero in storage
        assertEq(v2Params.vetoStartDate, 0, "vetoStartDate should be 0 for V1 proposals");
    }

    // =========================================================================
    // Storage: proposal data integrity
    // =========================================================================

    function test_UpgradeV1ToV2_PreservesVetoTally() public {
        uint256 proposalId = _createV1Proposal();

        // Alice vetoes on V1
        v1Plugin.veto(proposalId);

        (,,, uint256 tallyBefore,,,) = v1Plugin.getProposal(proposalId);
        assertGt(tallyBefore, 0, "Should have veto tally");

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        (,,, uint256 tallyAfter,,,) = v2.getProposal(proposalId);
        assertEq(tallyAfter, tallyBefore, "vetoTally changed");
    }

    function test_UpgradeV1ToV2_PreservesVetoVoterTracking() public {
        uint256 proposalId = _createV1Proposal();

        v1Plugin.veto(proposalId);
        assertTrue(v1Plugin.hasVetoed(proposalId, alice), "Alice should have vetoed on V1");

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        assertTrue(v2.hasVetoed(proposalId, alice), "Alice's veto lost after upgrade");
        assertFalse(v2.hasVetoed(proposalId, bob), "Bob should not have vetoed");
    }

    function test_UpgradeV1ToV2_PreservesMetadataAndActions() public {
        // Create proposal with actions
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0] = IDAO.Action({to: address(0xdead), value: 0, data: hex"cafebabe"});
        uint256 proposalId = v1Plugin.createProposal("ipfs://test-metadata", actions, 0, 4 days);

        (,,,, bytes memory metaBefore, IDAO.Action[] memory actionsBefore,) = v1Plugin.getProposal(proposalId);

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        (,,,, bytes memory metaAfter, IDAO.Action[] memory actionsAfter,) = v2.getProposal(proposalId);

        assertEq(keccak256(metaAfter), keccak256(metaBefore), "metadata changed");
        assertEq(actionsAfter.length, actionsBefore.length, "actions length changed");
        assertEq(actionsAfter[0].to, actionsBefore[0].to, "action.to changed");
        assertEq(actionsAfter[0].data, actionsBefore[0].data, "action.data changed");
    }

    function test_UpgradeV1ToV2_PreservesProposalCount() public {
        _createV1Proposal();
        _createV1Proposal();

        uint256 countBefore = v1Plugin.proposalCount();
        assertEq(countBefore, 2);

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        assertEq(v2.proposalCount(), countBefore, "proposalCount changed");
    }

    // =========================================================================
    // Functional: V1 proposals still work after upgrade
    // =========================================================================

    function test_UpgradeV1ToV2_CanVetoOldProposal() public {
        uint256 proposalId = _createV1Proposal();

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        // Bob vetoes through V2
        vm.stopPrank();
        vm.prank(bob);
        v2.veto(proposalId);

        assertTrue(v2.hasVetoed(proposalId, bob), "Bob's veto not recorded");
    }

    function test_UpgradeV1ToV2_CanExecuteOldProposal() public {
        uint256 proposalId = _createV1Proposal();

        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        // Warp past veto end + l2 grace + timelock
        (,, uint32 timelockPeriod,, uint32 l2AggregationGracePeriod,) = v2.governanceSettings();
        vm.warp(block.timestamp + 4 days + l2AggregationGracePeriod + timelockPeriod);

        assertTrue(v2.canExecute(proposalId), "Should be executable after upgrade");
        v2.execute(proposalId);

        (, bool executed,,,,,) = v2.getProposal(proposalId);
        assertTrue(executed, "Should be marked executed");
    }

    // =========================================================================
    // Functional: new V2 features work for new proposals
    // =========================================================================

    function test_UpgradeV1ToV2_NewProposalsHaveVetoStartDate() public {
        OptimisticTokenVotingPlugin v2 = _upgradeToV2();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = v2.createProposal("ipfs://", actions, 0, 4 days);

        (,, IOptimisticTokenVoting.ProposalParameters memory params,,,,) = v2.getProposal(proposalId);

        assertEq(params.vetoStartDate, uint64(block.timestamp), "vetoStartDate should be set for new proposals");
        assertGt(params.vetoEndDate, params.vetoStartDate, "vetoEndDate should be after vetoStartDate");
    }

    // =========================================================================
    // Raw storage: byte-level proof
    // =========================================================================

    function test_UpgradeV1ToV2_RawStorageProposalParametersSlot() public {
        uint256 proposalId = _createV1Proposal();

        // Read V1 params
        (,, OptimisticTokenVotingPluginV1.ProposalParameters memory v1Params,,,,) = v1Plugin.getProposal(proposalId);

        // Read raw storage slot for ProposalParameters
        // proposals mapping is at slot 355, ProposalParameters is at offset +1 within the Proposal struct
        bytes32 proposalBaseSlot = keccak256(abi.encode(proposalId, uint256(355)));
        bytes32 paramsSlot = bytes32(uint256(proposalBaseSlot) + 1);

        bytes32 rawBefore = vm.load(proxyAddr, paramsSlot);

        // Upgrade
        _upgradeToV2();

        bytes32 rawAfter = vm.load(proxyAddr, paramsSlot);

        // The raw storage must be identical — the upgrade changes code, not storage
        assertEq(rawAfter, rawBefore, "Raw ProposalParameters storage slot changed after upgrade");

        // Decode the raw slot to verify individual fields
        // Layout: [vetoEndDate:0-7][snapshotTimestamp:8-15][minVetoRatio:16-19][unavailableL2:20][vetoStartDate:21-28]
        uint64 rawVetoEndDate = uint64(uint256(rawAfter));
        uint64 rawSnapshot = uint64(uint256(rawAfter) >> 64);
        uint32 rawMinVetoRatio = uint32(uint256(rawAfter) >> 128);
        bool rawUnavailableL2 = uint8(uint256(rawAfter) >> 160) != 0;
        uint64 rawVetoStartDate = uint64(uint256(rawAfter) >> 168);

        assertEq(rawVetoEndDate, v1Params.vetoEndDate, "Raw vetoEndDate mismatch");
        assertEq(rawSnapshot, v1Params.snapshotTimestamp, "Raw snapshotTimestamp mismatch");
        assertEq(rawMinVetoRatio, v1Params.minVetoRatio, "Raw minVetoRatio mismatch");
        assertEq(rawUnavailableL2, v1Params.unavailableL2, "Raw unavailableL2 mismatch");
        assertEq(rawVetoStartDate, 0, "Raw vetoStartDate should be 0 for V1 proposals");
    }
}
