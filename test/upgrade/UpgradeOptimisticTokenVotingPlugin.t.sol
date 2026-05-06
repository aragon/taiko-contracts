// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {E2ETestBase} from "../base/E2ETestBase.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {TaikoBridgeMock} from "../mocks/TaikoBridgeMock.sol";
import {IBridge} from "../../src/interfaces/IBridge.sol";

contract UpgradeOptimisticTokenVotingPluginFactoryTest is E2ETestBase {
    TaikoBridgeMock taikoBridge;
    uint64 l2ChainId = 167000;

    function setUp() public {
        _install();

        taikoBridge = new TaikoBridgeMock();
        _deployL2VetoReceiver(address(taikoBridge), l2ChainId);
        _initUpgradeFactory();
    }

    // =========================================================================
    // Pre-upgrade sanity checks
    // =========================================================================

    function test_IsInstalledCorrectly() public view {
        assertEq(address(plugin.votingToken()), address(votingToken), "Token mismatch");
        assertEq(plugin.l2VetoReceiver(), address(0), "L2 receiver should be zero before upgrade");

        (uint32 minVetoRatio,,,,,) = plugin.governanceSettings();
        assertEq(minVetoRatio, uint32(RATIO_BASE / 10), "Settings mismatch");
    }

    // =========================================================================
    // Implementation upgrade
    // =========================================================================

    function test_UpgradeChangesImplementation() public {
        _runUpgrade();

        address implAfter = plugin.implementation();
        assertTrue(implAfter != implBefore, "Implementation should have changed");
        assertEq(implAfter, upgradeFactory.newSetup().implementation(), "Should match new setup implementation");
    }

    function test_UpgradeRegistersBuild2InRepo() public {
        _runUpgrade();

        assertEq(pluginRepo.buildCount(1), 2, "Should have 2 builds in release 1");
        PluginRepo.Version memory v2 = pluginRepo.getVersion(PluginRepo.Tag(1, 2));
        assertEq(v2.pluginSetup, address(upgradeFactory.newSetup()), "Build 2 should point to new setup");
    }

    // =========================================================================
    // L2 veto receiver configuration
    // =========================================================================

    function test_FinalizeSetsL2VetoReceiver() public {
        _runUpgrade();
        _runFinalize();

        assertEq(plugin.l2VetoReceiver(), address(l2VetoReceiver), "L2 receiver not set");
    }

    // =========================================================================
    // Finalize (DAO sets trusted aggregator directly)
    // =========================================================================

    function test_UpgradeGrantsDaoAggregatorPermission() public {
        _runUpgrade();

        assertTrue(
            dao.hasPermission(
                address(l2VetoReceiver),
                address(dao),
                l2VetoReceiver.SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID(),
                bytes("")
            ),
            "DAO should have SET_TRUSTED_L2_AGGREGATOR after upgrade"
        );
    }

    function test_FinalizeSetsTrustedL2Aggregator() public {
        _runUpgrade();
        _runFinalize();

        assertEq(l2VetoReceiver.trustedL2Aggregator(), trustedL2Aggregator, "Trusted L2 aggregator not set");
    }

    // =========================================================================
    // State preservation
    // =========================================================================

    function test_UpgradePreservesGovernanceSettings() public {
        (
            uint32 minVetoRatioBefore,
            uint32 minDurationBefore,
            uint32 timelockBefore,
            uint32 l2InactivityBefore,
            uint32 l2AggGraceBefore,
            bool skipL2Before
        ) = plugin.governanceSettings();

        _runUpgrade();

        (
            uint32 minVetoRatioAfter,
            uint32 minDurationAfter,
            uint32 timelockAfter,
            uint32 l2InactivityAfter,
            uint32 l2AggGraceAfter,
            bool skipL2After
        ) = plugin.governanceSettings();

        assertEq(minVetoRatioAfter, minVetoRatioBefore, "minVetoRatio changed");
        assertEq(minDurationAfter, minDurationBefore, "minDuration changed");
        assertEq(timelockAfter, timelockBefore, "timelockPeriod changed");
        assertEq(l2InactivityAfter, l2InactivityBefore, "l2InactivityPeriod changed");
        assertEq(l2AggGraceAfter, l2AggGraceBefore, "l2AggregationGracePeriod changed");
        assertEq(skipL2After, skipL2Before, "skipL2 changed");
    }

    function test_UpgradePreservesTokenAndAddresses() public {
        address tokenBefore = address(plugin.votingToken());
        address taikoL1Before = address(plugin.taikoL1());
        address vaultBefore = plugin.taikoERC20Vault();

        _runUpgrade();

        assertEq(address(plugin.votingToken()), tokenBefore, "votingToken changed");
        assertEq(address(plugin.taikoL1()), taikoL1Before, "taikoL1 changed");
        assertEq(plugin.taikoERC20Vault(), vaultBefore, "taikoERC20Vault changed");
    }

    // =========================================================================
    // Permission cleanup
    // =========================================================================

    function test_UpgradeRevokesFactoryRoot() public {
        _runUpgrade();

        assertFalse(
            dao.hasPermission(address(dao), address(upgradeFactory), dao.ROOT_PERMISSION_ID(), bytes("")),
            "Factory should not have ROOT after upgrade"
        );
    }

    function test_UpgradeRevokesPspRoot() public {
        _runUpgrade();

        assertFalse(
            dao.hasPermission(address(dao), address(psp), dao.ROOT_PERMISSION_ID(), bytes("")),
            "PSP should not have ROOT after upgrade"
        );
    }

    function test_UpgradeRevokesUpgradePluginFromPsp() public {
        _runUpgrade();

        assertFalse(
            dao.hasPermission(address(plugin), address(psp), plugin.UPGRADE_PLUGIN_PERMISSION_ID(), bytes("")),
            "PSP should not have UPGRADE_PLUGIN after upgrade"
        );
    }

    function test_UpgradeRevokesApplyUpdateFromFactory() public {
        _runUpgrade();

        assertFalse(
            dao.hasPermission(address(psp), address(upgradeFactory), psp.APPLY_UPDATE_PERMISSION_ID(), bytes("")),
            "Factory should not have APPLY_UPDATE after upgrade"
        );
    }

    function test_UpgradeGrantsDaoL2VetoReceiverPermission() public {
        _runUpgrade();

        assertTrue(
            dao.hasPermission(address(plugin), address(dao), plugin.UPDATE_L2_VETO_RECEIVER_PERMISSION_ID(), bytes("")),
            "DAO should have UPDATE_L2_VETO_RECEIVER after upgrade"
        );
    }

    // =========================================================================
    // Post-upgrade plugin functionality
    // =========================================================================

    function test_CanCreateProposalAfterUpgrade() public {
        _runUpgrade();

        vm.warp(block.timestamp + plugin.SNAPSHOT_OFFSET());
        vm.roll(block.number + 1);

        vm.prank(alice);
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal("ipfs://", actions, 0, 10 days);

        (bool open,,,,,,) = plugin.getProposal(proposalId);
        assertTrue(open, "Proposal should be open");
    }

    function test_CanVetoAfterUpgrade() public {
        _runUpgrade();

        vm.warp(block.timestamp + plugin.SNAPSHOT_OFFSET());
        vm.roll(block.number + 1);

        vm.prank(alice);
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal("ipfs://", actions, 0, 10 days);

        vm.prank(alice);
        plugin.veto(proposalId);

        assertTrue(plugin.hasVetoed(proposalId, alice), "Veto should be recorded");
    }

    // =========================================================================
    // Full deployment: upgrade() + finalize()
    // =========================================================================

    function test_FullDeployment() public {
        _runUpgrade();
        _runFinalize();

        assertTrue(plugin.implementation() != implBefore, "Implementation should have changed");
        assertEq(plugin.l2VetoReceiver(), address(l2VetoReceiver), "L2 receiver not set");
        assertEq(l2VetoReceiver.trustedL2Aggregator(), trustedL2Aggregator, "Aggregator not set");

        // Factory permissions cleaned up
        assertFalse(
            dao.hasPermission(address(dao), address(upgradeFactory), dao.ROOT_PERMISSION_ID(), bytes("")),
            "Factory should not have ROOT"
        );
        assertFalse(
            dao.hasPermission(address(dao), address(psp), dao.ROOT_PERMISSION_ID(), bytes("")),
            "PSP should not have ROOT"
        );

        // DAO retains aggregator permission
        assertTrue(
            dao.hasPermission(
                address(l2VetoReceiver),
                address(dao),
                l2VetoReceiver.SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID(),
                bytes("")
            ),
            "DAO should have SET_TRUSTED_L2_AGGREGATOR"
        );

        vm.warp(block.timestamp + plugin.SNAPSHOT_OFFSET());
        vm.roll(block.number + 1);

        vm.prank(alice);
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal("ipfs://", actions, 0, 10 days);

        (bool open,,,,,,) = plugin.getProposal(proposalId);
        assertTrue(open, "Proposal should be open after full deployment");
    }

    // =========================================================================
    // E2E: Full deployment + crosschain L2 veto delivery
    // =========================================================================

    function test_FullDeployment_L2VetosReachPlugin() public {
        _runUpgrade();
        _runFinalize();

        (uint256 proposalId, uint64 vetoEndDate) = _mintVaultTokensAndCreateProposal();

        (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        assertFalse(params.unavailableL2, "L2 should be available for this proposal");

        vm.warp(vetoEndDate + 1);

        uint256 vetoTally = 2 ether;
        uint256 dispatchedAt = block.timestamp;
        bytes memory vetoData = abi.encode(proposalId, vetoTally, dispatchedAt);

        IBridge.Message memory message = IBridge.Message({
            id: 0,
            fee: 0,
            gasLimit: 200_000,
            from: trustedL2Aggregator,
            srcChainId: l2ChainId,
            srcOwner: trustedL2Aggregator,
            destChainId: uint64(block.chainid),
            destOwner: address(l2VetoReceiver),
            to: address(l2VetoReceiver),
            value: 0,
            data: abi.encodeCall(l2VetoReceiver.onMessageInvocation, (vetoData))
        });

        (IBridge.Status status,) = taikoBridge.processMessage(message, "");
        assertEq(uint256(status), uint256(IBridge.Status.DONE), "Bridge message should succeed");

        assertEq(l2VetoReceiver.getL2VetoTally(proposalId), vetoTally, "Receiver should store L2 veto tally");
        assertEq(
            l2VetoReceiver.getL2DispatchTimestamp(proposalId), dispatchedAt, "Receiver should store dispatch timestamp"
        );
        assertTrue(l2VetoReceiver.hasReceivedL2Vetoes(proposalId), "Receiver should mark L2 vetoes received");

        (,,, uint256 pluginVetoTally,,,) = plugin.getProposal(proposalId);
        assertEq(pluginVetoTally, vetoTally, "Plugin vetoTally should reflect L2 vetoes");
    }
}
