// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {
    UpgradeOptimisticTokenVotingPluginFactory
} from "../src/factory/UpgradeOptimisticTokenVotingPluginFactory.sol";
import {L2VetoReceiver} from "../src/crosschain/L2VetoReceiver.sol";

/// @title UpgradeOptimisticTokenVotingPlugin
/// @notice Deploys L2VetoReceiver + UpgradeFactory and logs the DAO proposal actions.
/// @dev Deployment flow:
///      1. Run this script (L1) — deploys L2VetoReceiver + UpgradeFactory
///      2. DAO Proposal 1: upgrade() — plugin upgrade + sets L2VetoReceiver
///      3. Deploy L2VetoAggregator on L2 (using the receiver address from step 1)
///      4. DAO Proposal 2: configureTrustedL2Aggregator() — sets aggregator on receiver
contract UpgradeOptimisticTokenVotingPlugin is Script {
    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        _;

        vm.stopBroadcast();
    }

    function run() external broadcast {
        address dao = vm.envAddress("DAO_ADDRESS");
        address plugin = vm.envAddress("PLUGIN_ADDRESS");
        address pluginRepo = vm.envAddress("PLUGIN_REPO_ADDRESS");
        address psp = vm.envAddress("PLUGIN_SETUP_PROCESSOR");
        address governanceERC20Base = vm.envAddress("GOVERNANCE_ERC20_BASE");
        address governanceWrappedERC20Base = vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE");
        address votingToken = vm.envAddress("L1_VOTING_TOKEN");
        address taikoBridge = vm.envAddress("L1_TAIKO_BRIDGE");
        uint64 l2ChainId = uint64(vm.envUint("L2_CHAIN_ID"));

        // Deploy L2VetoReceiver (L1)
        L2VetoReceiver l2VetoReceiver = new L2VetoReceiver(IDAO(dao), taikoBridge, l2ChainId, plugin);
        console.log("L2VetoReceiver deployed at:", address(l2VetoReceiver));

        // Deploy factory (which deploys the new PluginSetup internally)
        UpgradeOptimisticTokenVotingPluginFactory factory = new UpgradeOptimisticTokenVotingPluginFactory(
            GovernanceERC20(governanceERC20Base), GovernanceWrappedERC20(governanceWrappedERC20Base)
        );

        console.log("UpgradeFactory deployed at:", address(factory));
        console.log("New PluginSetup:", address(factory.newSetup()));
        console.log("New implementation:", factory.newSetup().implementation());

        // Build upgrade params
        UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams memory params =
            UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams({
                dao: DAO(payable(dao)),
                psp: PluginSetupProcessor(psp),
                plugin: OptimisticTokenVotingPlugin(plugin),
                pluginRepo: PluginRepo(pluginRepo),
                votingToken: votingToken,
                l2VetoReceiver: address(l2VetoReceiver)
            });

        console.log("");
        console.log("=== DAO Proposal 1: Plugin Upgrade ===");
        console.log("");
        console.log("Action 1: Grant ROOT on DAO to factory");
        console.log("  to:", dao);
        console.log("  data: dao.grant(dao, factory, ROOT_PERMISSION_ID)");
        console.log("");
        console.log("Action 2: Grant MAINTAINER on PluginRepo to factory");
        console.log("  to:", pluginRepo);
        console.log("  data: pluginRepo.grant(pluginRepo, factory, MAINTAINER_PERMISSION_ID)");
        console.log("");
        console.log("Action 3: Call factory.upgrade()");
        console.log("  to:", address(factory));
        console.log("");
        console.log("Action 4: Revoke MAINTAINER on PluginRepo from factory");
        console.log("  to:", pluginRepo);
        console.log("  data: pluginRepo.revoke(pluginRepo, factory, MAINTAINER_PERMISSION_ID)");
        console.log("");
        console.log("Encoded factory.upgrade() calldata:");
        console.logBytes(abi.encodeCall(UpgradeOptimisticTokenVotingPluginFactory.upgrade, (params)));

        console.log("");
        console.log("=== DAO Proposal 2: Finalize (after deploying L2VetoAggregator on L2) ===");
        console.log("");
        console.log("Action 1: Grant ROOT on DAO to factory");
        console.log("  to:", dao);
        console.log("  data: dao.grant(dao, factory, ROOT_PERMISSION_ID)");
        console.log("");
        console.log("Action 2: Call factory.finalize(dao, l2VetoReceiver, aggregator)");
        console.log("  to:", address(factory));
        console.log("  l2VetoReceiver:", address(l2VetoReceiver));
        console.log("  trustedL2Aggregator: <L2_VETO_AGGREGATOR_ADDRESS from L2 deployment>");

        console.log("");
        console.log("=== Next steps ===");
        console.log("1. Submit DAO Proposal 1 (plugin upgrade)");
        console.log("2. Set L2_VETO_RECEIVER_ADDRESS=", address(l2VetoReceiver), " in taiko-hoodi .env");
        console.log("3. Deploy L2VetoAggregator on L2");
        console.log("4. Submit DAO Proposal 2 (configure aggregator)");
    }
}
