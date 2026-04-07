// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {ScriptBase} from "../lib/ScriptBase.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {IPermissionCondition} from "@aragon/osx/core/permission/IPermissionCondition.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {
    UpgradeOptimisticTokenVotingPluginFactory
} from "../../src/factory/UpgradeOptimisticTokenVotingPluginFactory.sol";
import {L2VetoReceiver} from "../../src/crosschain/L2VetoReceiver.sol";

/// @title EncodeProposal (Upgrade)
/// @notice Generates the single DAO proposal JSON for the full upgrade.
/// @dev Step 3 of 3. Run against L1 RPC (reads on-chain permission constants).
///      Requires deployed addresses from steps 1-2.
///      No broadcast — only encodes calldata and writes JSON.
contract EncodeProposal is ScriptBase {
    struct Config {
        address dao;
        address plugin;
        address pluginRepo;
        address psp;
        address l1VotingToken;
        address vetoReceiver;
        address vetoAggregator;
        address upgradeFactory;
        address stdProposer;
        address stdProposalCondition;
    }

    function run() external {
        Config memory config = _loadConfig();

        IDAO.Action[] memory actions = new IDAO.Action[](7);
        _buildUpgradeActions(config, actions);
        _buildProposerFixActions(config, actions);

        _writeProposal("proposal-upgrade-l2-veto", actions);
        _logActions(actions);
    }

    function _buildUpgradeActions(Config memory config, IDAO.Action[] memory actions) internal view {
        UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams memory params =
            UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams({
                dao: DAO(payable(config.dao)),
                psp: PluginSetupProcessor(config.psp),
                plugin: OptimisticTokenVotingPlugin(config.plugin),
                pluginRepo: PluginRepo(config.pluginRepo),
                votingToken: config.l1VotingToken,
                l2VetoReceiver: config.vetoReceiver
            });

        bytes32 rootPermission = DAO(payable(config.dao)).ROOT_PERMISSION_ID();
        bytes32 maintainerPermission = PluginRepo(config.pluginRepo).MAINTAINER_PERMISSION_ID();

        actions[0] = IDAO.Action({
            to: config.dao,
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (config.dao, config.upgradeFactory, rootPermission))
        });
        actions[1] = IDAO.Action({
            to: config.pluginRepo,
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant, (config.pluginRepo, config.upgradeFactory, maintainerPermission)
            )
        });
        actions[2] = IDAO.Action({
            to: config.upgradeFactory,
            value: 0,
            data: abi.encodeCall(UpgradeOptimisticTokenVotingPluginFactory.upgrade, (params))
        });
        actions[3] = IDAO.Action({
            to: config.pluginRepo,
            value: 0,
            data: abi.encodeCall(
                PermissionManager.revoke, (config.pluginRepo, config.upgradeFactory, maintainerPermission)
            )
        });
        actions[4] = IDAO.Action({
            to: config.vetoReceiver,
            value: 0,
            data: abi.encodeCall(L2VetoReceiver.setTrustedL2Aggregator, (config.vetoAggregator))
        });
    }

    function _buildProposerFixActions(Config memory config, IDAO.Action[] memory actions) internal pure {
        bytes32 proposerPermission = keccak256("PROPOSER_PERMISSION");

        // Revoke unconditional PROPOSER_PERMISSION and re-grant with condition
        actions[5] = IDAO.Action({
            to: config.dao,
            value: 0,
            data: abi.encodeCall(PermissionManager.revoke, (config.plugin, config.stdProposer, proposerPermission))
        });
        actions[6] = IDAO.Action({
            to: config.dao,
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grantWithCondition,
                (
                    config.plugin,
                    config.stdProposer,
                    proposerPermission,
                    IPermissionCondition(config.stdProposalCondition)
                )
            )
        });
    }

    function _loadConfig() internal view returns (Config memory) {
        return Config({
            dao: vm.envAddress("DAO_ADDRESS"),
            plugin: vm.envAddress("PLUGIN_ADDRESS"),
            pluginRepo: vm.envAddress("PLUGIN_REPO_ADDRESS"),
            psp: vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS"),
            l1VotingToken: vm.envAddress("L1_VOTING_TOKEN"),
            vetoReceiver: vm.envAddress("VETO_RECEIVER_ADDRESS"),
            vetoAggregator: vm.envAddress("VETO_AGGREGATOR_ADDRESS"),
            upgradeFactory: vm.envAddress("UPGRADE_FACTORY_ADDRESS"),
            stdProposer: vm.envAddress("MULTISIG_PLUGIN_ADDRESS"),
            stdProposalCondition: vm.envAddress("STANDARD_PROPOSAL_CONDITION")
        });
    }
}
