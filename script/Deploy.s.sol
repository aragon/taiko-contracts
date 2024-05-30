// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {TaikoDaoFactory} from "../src/factory/TaikoDaoFactory.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {Multisig} from "../src/Multisig.sol";
import {EmergencyMultisig} from "../src/EmergencyMultisig.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {PublicKeyRegistry} from "../src/PublicKeyRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

contract Deploy is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_PRIVATE_KEY"));

        // JSON list of members
        string memory path = string.concat(vm.projectRoot(), "/script/multisig-members.json");
        string memory json = vm.readFile(path);

        TaikoDaoFactory.DeploymentSettings memory settings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: IVotesUpgradeable(vm.envAddress("TOKEN_ADDRESS")),
            taikoL1ContractAddress: vm.envAddress("TAIKO_L1_ADDRESS"),
            taikoBridgeAddress: vm.envAddress("TAIKO_BRIDGE_ADDRESS"),
            l2InactivityPeriod: uint64(vm.envUint("L2_INACTIVITY_PERIOD")),
            l2AggregationGracePeriod: uint64(vm.envUint("L2_AGGREGATION_GRACE_PERIOD")),
            // Voting settings
            minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
            minStdProposalDelay: uint64(vm.envUint("MIN_STD_PROPOSAL_DELAY")),
            minStdApprovals: uint16(vm.envUint("MIN_STD_APPROVALS")),
            minEmergencyApprovals: uint16(vm.envUint("MIN_EMERGENCY_APPROVALS")),
            // OSx contracts
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY")),
            // Token contracts
            governanceErc20Base: GovernanceERC20(vm.envAddress("GOVERNANCE_ERC20_BASE")),
            governanceErcWrapped20Base: GovernanceWrappedERC20(vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE")),
            // Multisig
            multisigMembers: vm.parseJsonAddressArray(json, "$.addresses"),
            // ENS
            stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
            emergencyMultisigEnsDomain: vm.envString("EMERGENCY_MULTISIG_ENS_DOMAIN"),
            optimisticTokenVotingEnsDomain: vm.envString("OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN")
        });

        TaikoDaoFactory factory = new TaikoDaoFactory(settings);
        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();

        vm.stopBroadcast();

        // Print summary
        console.log("Factory contract", address(this));
        console.log("");
        console.log("DAO contract", address(deployment.dao));
        console.log("");

        console.log("Multisig plugin", address(deployment.multisigPlugin));
        console.log("Emergency multisig plugin", address(deployment.emergencyMultisigPlugin));
        console.log("Optimistic token voting plugin", address(deployment.optimisticTokenVotingPlugin));
        console.log("");

        console.log("Multisig plugin repository", address(deployment.multisigPluginRepo));
        console.log("Emergency multisig plugin repository", address(deployment.emergencyMultisigPluginRepo));
        console.log("Optimistic token voting plugin repository", address(deployment.optimisticTokenVotingPluginRepo));
        console.log("");

        console.log("Public key registry", address(deployment.publicKeyRegistry));
    }
}
