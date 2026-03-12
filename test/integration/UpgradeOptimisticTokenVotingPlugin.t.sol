// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "../base/AragonTest.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {PluginSetupRef, hashHelpers} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {createProxyAndCall} from "../../src/helpers/proxy.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {OptimisticTokenVotingPluginSetup} from "../../src/setup/OptimisticTokenVotingPluginSetup.sol";
import {
    UpgradeOptimisticTokenVotingPluginFactory
} from "../../src/factory/UpgradeOptimisticTokenVotingPluginFactory.sol";
import {MockPluginSetupProcessor} from "../mocks/osx/MockPSP.sol";
import {MockPluginRepoRegistry} from "../mocks/osx/MockPluginRepoRegistry.sol";
import {GovernanceERC20Mock} from "../mocks/GovernanceERC20Mock.sol";
import {TaikoL1Mock} from "../mocks/TaikoL1Mock.sol";

contract UpgradeOptimisticTokenVotingPluginFactoryTest is AragonTest {
    DAO dao;
    OptimisticTokenVotingPlugin plugin;
    PluginRepo pluginRepo;
    MockPluginSetupProcessor psp;
    GovernanceERC20Mock votingToken;
    OptimisticTokenVotingPluginSetup initialSetup;
    UpgradeOptimisticTokenVotingPluginFactory upgradeFactory;

    address l2VetoReceiver = address(0xBEEF);
    address implBefore;

    function setUp() public {
        _install();

        implBefore = plugin.implementation();

        upgradeFactory = new UpgradeOptimisticTokenVotingPluginFactory(
            GovernanceERC20(address(1)), GovernanceWrappedERC20(address(1))
        );

        // Advance block so PSP state tracking works (install was in previous block)
        vm.roll(block.number + 1);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _install() internal {
        // Create DAO with `this` as ROOT
        dao = DAO(
            payable(createProxyAndCall(
                    address(new DAO()), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                ))
        );

        // Deploy voting token and mint
        votingToken = new GovernanceERC20Mock(address(dao));
        votingToken.mintAndDelegate(alice, 10 ether);

        // Create mock OSx infrastructure
        MockPluginRepoRegistry repoRegistry = new MockPluginRepoRegistry();
        PluginRepoFactory repoFactory = new PluginRepoFactory(PluginRepoRegistry(address(repoRegistry)));

        // Deploy initial setup (address(1) bases are fine since we pass an existing token)
        initialSetup =
            new OptimisticTokenVotingPluginSetup(GovernanceERC20(address(1)), GovernanceWrappedERC20(address(1)));

        // Create PluginRepo with Build 1 (this test contract = maintainer)
        pluginRepo = repoFactory.createPluginRepoWithFirstVersion(
            "optimistic-voting", address(initialSetup), address(this), bytes("0x00"), bytes("0x00")
        );

        // Create MockPSP with initial setup queued
        address[] memory setups = new address[](1);
        setups[0] = address(initialSetup);
        psp = new MockPluginSetupProcessor(setups);

        // Grant temporary permissions for installation
        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        dao.grant(address(psp), address(this), psp.APPLY_INSTALLATION_PERMISSION_ID());

        // Prepare installation
        bytes memory installData = initialSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters({
                votingSettings: OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 4 days,
                    timelockPeriod: 7 days,
                    l2InactivityPeriod: 10 minutes,
                    l2AggregationGracePeriod: 2 days,
                    skipL2: false
                }),
                tokenSettings: OptimisticTokenVotingPluginSetup.TokenSettings({
                    addr: address(votingToken), name: "", symbol: ""
                }),
                mintSettings: GovernanceERC20.MintSettings(new address[](0), new uint256[](0)),
                taikoL1: address(new TaikoL1Mock()),
                taikoERC20Vault: taikoERC20Vault,
                stdProposalMinDuration: 10 days,
                stdProposer: alice,
                emergencyProposer: alice
            })
        );

        PluginSetupRef memory setupRef = PluginSetupRef(PluginRepo.Tag(1, 1), pluginRepo);

        (address pluginAddr, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp.prepareInstallation(
            address(dao),
            MockPluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: setupRef, data: installData})
        );
        plugin = OptimisticTokenVotingPlugin(pluginAddr);

        psp.applyInstallation(
            address(dao),
            MockPluginSetupProcessor.ApplyInstallationParams({
                pluginSetupRef: setupRef,
                plugin: pluginAddr,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            })
        );

        // Revoke temporary installation permissions
        dao.revoke(address(psp), address(this), psp.APPLY_INSTALLATION_PERMISSION_ID());
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
    }

    function _runUpgrade() internal {
        // Grant ROOT on DAO to factory
        dao.grant(address(dao), address(upgradeFactory), dao.ROOT_PERMISSION_ID());

        // Grant MAINTAINER on repo to factory
        pluginRepo.grant(address(pluginRepo), address(upgradeFactory), pluginRepo.MAINTAINER_PERMISSION_ID());

        upgradeFactory.upgrade(
            UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams({
                dao: dao,
                psp: PluginSetupProcessor(address(psp)),
                plugin: plugin,
                pluginRepo: pluginRepo,
                votingToken: address(votingToken),
                l2VetoReceiver: l2VetoReceiver
            })
        );

        // Revoke MAINTAINER on repo from factory
        pluginRepo.revoke(address(pluginRepo), address(upgradeFactory), pluginRepo.MAINTAINER_PERMISSION_ID());
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

    function test_UpgradeSetsL2VetoReceiver() public {
        _runUpgrade();

        assertEq(plugin.l2VetoReceiver(), l2VetoReceiver, "L2 receiver not set");
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

    function test_UpgradeRevokesFactoryL2VetoReceiverPermission() public {
        _runUpgrade();

        assertFalse(
            dao.hasPermission(
                address(plugin), address(upgradeFactory), plugin.UPDATE_L2_VETO_RECEIVER_PERMISSION_ID(), bytes("")
            ),
            "Factory should not have UPDATE_L2_VETO_RECEIVER after upgrade"
        );
    }

    // =========================================================================
    // Post-upgrade plugin functionality
    // =========================================================================

    function test_CanCreateProposalAfterUpgrade() public {
        _runUpgrade();

        // Advance time and block so token checkpoints are available
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        vm.prank(alice);
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal("ipfs://", actions, 0, 4 days);

        (bool open,,,,,,) = plugin.getProposal(proposalId);
        assertTrue(open, "Proposal should be open");
    }

    function test_CanVetoAfterUpgrade() public {
        _runUpgrade();

        // Advance time and block so token checkpoints are available
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        vm.prank(alice);
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal("ipfs://", actions, 0, 4 days);

        vm.prank(alice);
        plugin.veto(proposalId);

        assertTrue(plugin.hasVetoed(proposalId, alice), "Veto should be recorded");
    }
}
