// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./AragonTest.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
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
import {L2VetoReceiver} from "../../src/crosschain/L2VetoReceiver.sol";

/// @notice Shared setup for tests that need a fully installed + upgraded plugin with L2VetoReceiver.
/// @dev Child contracts must call _install(), _deployL2VetoReceiver(), and _initUpgradeFactory() in setUp().
abstract contract UpgradeTestBase is AragonTest {
    DAO dao;
    OptimisticTokenVotingPlugin plugin;
    PluginRepo pluginRepo;
    MockPluginSetupProcessor psp;
    GovernanceERC20Mock votingToken;
    OptimisticTokenVotingPluginSetup initialSetup;
    UpgradeOptimisticTokenVotingPluginFactory upgradeFactory;

    L2VetoReceiver l2VetoReceiver;
    address trustedL2Aggregator = address(0xCAFE);
    address implBefore;

    function _install() internal {
        dao = DAO(
            payable(
                createProxyAndCall(
                    address(new DAO()), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        votingToken = new GovernanceERC20Mock(address(dao));
        votingToken.mintAndDelegate(alice, 10 ether);

        MockPluginRepoRegistry repoRegistry = new MockPluginRepoRegistry();
        PluginRepoFactory repoFactory = new PluginRepoFactory(PluginRepoRegistry(address(repoRegistry)));

        initialSetup =
            new OptimisticTokenVotingPluginSetup(GovernanceERC20(address(1)), GovernanceWrappedERC20(address(1)));

        pluginRepo = repoFactory.createPluginRepoWithFirstVersion(
            "optimistic-voting", address(initialSetup), address(this), bytes("0x00"), bytes("0x00")
        );

        address[] memory setups = new address[](1);
        setups[0] = address(initialSetup);
        psp = new MockPluginSetupProcessor(setups);

        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        dao.grant(address(psp), address(this), psp.APPLY_INSTALLATION_PERMISSION_ID());

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

        dao.revoke(address(psp), address(this), psp.APPLY_INSTALLATION_PERMISSION_ID());
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
    }

    function _deployL2VetoReceiver(address _bridge, uint64 _l2ChainId) internal {
        l2VetoReceiver = new L2VetoReceiver(IDAO(address(dao)), _bridge, _l2ChainId, address(plugin));
    }

    function _initUpgradeFactory() internal {
        implBefore = plugin.implementation();
        upgradeFactory = new UpgradeOptimisticTokenVotingPluginFactory(
            GovernanceERC20(address(1)), GovernanceWrappedERC20(address(1))
        );
        vm.roll(block.number + 1);
    }

    function _runUpgrade() internal {
        dao.grant(address(dao), address(upgradeFactory), dao.ROOT_PERMISSION_ID());
        pluginRepo.grant(address(pluginRepo), address(upgradeFactory), pluginRepo.MAINTAINER_PERMISSION_ID());

        upgradeFactory.upgrade(
            UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams({
                dao: dao,
                psp: PluginSetupProcessor(address(psp)),
                plugin: plugin,
                pluginRepo: pluginRepo,
                votingToken: address(votingToken),
                l2VetoReceiver: address(l2VetoReceiver)
            })
        );

        pluginRepo.revoke(address(pluginRepo), address(upgradeFactory), pluginRepo.MAINTAINER_PERMISSION_ID());
    }

    function _runFinalize() internal {
        dao.grant(address(dao), address(upgradeFactory), dao.ROOT_PERMISSION_ID());
        upgradeFactory.finalize(dao, address(l2VetoReceiver), trustedL2Aggregator);
    }

    /// @dev Mints to vault so L2 is enabled, advances time, creates proposal as alice.
    function _mintVaultTokensAndCreateProposal()
        internal
        returns (uint256 proposalId, uint64 vetoEndDate)
    {
        votingToken.mintAndDelegate(taikoERC20Vault, 5 ether);

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        vm.prank(alice);
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        proposalId = plugin.createProposal("ipfs://e2e", actions, 0, 4 days);

        (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vetoEndDate = params.vetoEndDate;
    }
}
