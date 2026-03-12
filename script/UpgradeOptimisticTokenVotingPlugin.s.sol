// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {
    UpgradeOptimisticTokenVotingPluginFactory
} from "../src/factory/UpgradeOptimisticTokenVotingPluginFactory.sol";

/// @title UpgradeOptimisticTokenVotingPlugin
/// @notice Deploys the UpgradeFactory and logs the four actions needed for a DAO proposal:
///         1. Grant ROOT to the factory
///         2. Grant MAINTAINER on the PluginRepo to the factory
///         3. Call factory.upgrade()
///         4. Revoke MAINTAINER from the factory
/// @dev After upgrade() completes, the factory revokes its own ROOT - single-use.
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
        address votingToken = vm.envAddress("VOTING_TOKEN_ADDRESS");
        address l2VetoReceiver = vm.envAddress("L2_VETO_RECEIVER_ADDRESS");

        // Deploy factory (which deploys the new PluginSetup internally)
        UpgradeOptimisticTokenVotingPluginFactory factory = new UpgradeOptimisticTokenVotingPluginFactory(
            GovernanceERC20(governanceERC20Base), GovernanceWrappedERC20(governanceWrappedERC20Base)
        );

        console.log("UpgradeFactory deployed at:", address(factory));
        console.log("New PluginSetup:", address(factory.newSetup()));
        console.log("New implementation:", factory.newSetup().implementation());

        console.log("");
        console.log("=== DAO Proposal Actions ===");
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

        // Build the upgrade params for reference
        UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams memory params =
            UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams({
                dao: DAO(payable(dao)),
                psp: PluginSetupProcessor(psp),
                plugin: OptimisticTokenVotingPlugin(plugin),
                pluginRepo: PluginRepo(pluginRepo),
                votingToken: votingToken,
                l2VetoReceiver: l2VetoReceiver
            });

        console.log("");
        console.log("Action 4: Revoke MAINTAINER on PluginRepo from factory");
        console.log("  to:", pluginRepo);
        console.log("  data: pluginRepo.revoke(pluginRepo, factory, MAINTAINER_PERMISSION_ID)");

        console.log("");
        console.log("Encoded factory.upgrade() calldata:");
        console.logBytes(abi.encodeCall(UpgradeOptimisticTokenVotingPluginFactory.upgrade, (params)));
    }
}
