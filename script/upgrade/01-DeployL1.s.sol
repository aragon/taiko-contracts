// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {ScriptBase} from "../lib/ScriptBase.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {
    UpgradeOptimisticTokenVotingPluginFactory
} from "../../src/factory/UpgradeOptimisticTokenVotingPluginFactory.sol";
import {L2VetoReceiver} from "../../src/crosschain/L2VetoReceiver.sol";

/// @title DeployL1 (Upgrade)
/// @notice Deploys L2VetoReceiver + UpgradeFactory on L1.
/// @dev Step 1 of 3. Run against the L1 RPC.
///      All upgrade params are fixed at factory construction time.
contract DeployL1 is ScriptBase {
    struct Config {
        uint256 privKey;
        address dao;
        address plugin;
        address pluginRepo;
        address psp;
        address l1VotingToken;
        address l1TaikoBridge;
        uint64 l2ChainId;
        address governanceERC20Base;
        address governanceWrappedERC20Base;
    }

    function run() external {
        Config memory config = _loadConfig();

        vm.startBroadcast(config.privKey);

        L2VetoReceiver receiver =
            new L2VetoReceiver(IDAO(config.dao), config.l1TaikoBridge, config.l2ChainId, config.plugin);
        console.log("L2VetoReceiver:", address(receiver));

        UpgradeOptimisticTokenVotingPluginFactory factory = new UpgradeOptimisticTokenVotingPluginFactory(
            GovernanceERC20(config.governanceERC20Base),
            GovernanceWrappedERC20(config.governanceWrappedERC20Base),
            DAO(payable(config.dao)),
            PluginSetupProcessor(config.psp),
            OptimisticTokenVotingPlugin(config.plugin),
            PluginRepo(config.pluginRepo),
            config.l1VotingToken,
            address(receiver)
        );
        console.log("UpgradeFactory:", address(factory));
        console.log("  New PluginSetup:", address(factory.newSetup()));
        console.log("  New implementation:", factory.newSetup().implementation());

        vm.stopBroadcast();

        string memory key = "l1";
        vm.serializeAddress(key, "l2VetoReceiver", address(receiver));
        vm.serializeAddress(key, "upgradeFactory", address(factory));
        vm.serializeAddress(key, "newPluginSetup", address(factory.newSetup()));
        string memory json = vm.serializeAddress(key, "newImplementation", factory.newSetup().implementation());

        _writeDeployment("upgrade/01-DeployL1.s.sol", json);

        console.log("");
        console.log("Next: run 02-DeployL2.s.sol against L2 RPC");
    }

    function _loadConfig() internal view returns (Config memory) {
        return Config({
            privKey: vm.envUint("DEPLOYMENT_PRIVATE_KEY"),
            dao: vm.envAddress("DAO_ADDRESS"),
            plugin: vm.envAddress("PLUGIN_ADDRESS"),
            pluginRepo: vm.envAddress("PLUGIN_REPO_ADDRESS"),
            psp: vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS"),
            l1VotingToken: vm.envAddress("L1_VOTING_TOKEN"),
            l1TaikoBridge: vm.envAddress("L1_TAIKO_BRIDGE"),
            l2ChainId: uint64(vm.envUint("L2_CHAIN_ID")),
            governanceERC20Base: vm.envAddress("GOVERNANCE_ERC20_BASE"),
            governanceWrappedERC20Base: vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE")
        });
    }
}
