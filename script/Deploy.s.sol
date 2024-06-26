// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {TaikoDaoFactory} from "../src/factory/TaikoDaoFactory.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {Multisig} from "../src/Multisig.sol";
import {MultisigPluginSetup} from "../src/setup/MultisigPluginSetup.sol";
import {EmergencyMultisig} from "../src/EmergencyMultisig.sol";
import {EmergencyMultisigPluginSetup} from "../src/setup/EmergencyMultisigPluginSetup.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {OptimisticTokenVotingPluginSetup} from "../src/setup/OptimisticTokenVotingPluginSetup.sol";
import {PublicKeyRegistry} from "../src/PublicKeyRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {GovernanceERC20Mock} from "../test/mocks/GovernanceERC20Mock.sol";
import {TaikoL1Mock} from "../test/mocks/TaikoL1Mock.sol";

contract Deploy is Script {
    MultisigPluginSetup multisigPluginSetup;
    EmergencyMultisigPluginSetup emergencyMultisigPluginSetup;
    OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup;

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_PRIVATE_KEY"));

        // Deploy the plugin setup's
        multisigPluginSetup = new MultisigPluginSetup();
        emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        optimisticTokenVotingPluginSetup = new OptimisticTokenVotingPluginSetup(
            GovernanceERC20(vm.envAddress("GOVERNANCE_ERC20_BASE")),
            GovernanceWrappedERC20(vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE"))
        );

        console.log("Chain ID:", block.chainid);
        console.log("Deploying from:", vm.addr(vm.envUint("DEPLOYMENT_PRIVATE_KEY")));
        console.log("");

        TaikoDaoFactory.DeploymentSettings memory settings;
        if (block.chainid == 1) {
            settings = getMainnetSettings();
        } else {
            settings = getTestnetSettings();
        }

        TaikoDaoFactory factory = new TaikoDaoFactory(settings);
        factory.deployOnce();
        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();

        vm.stopBroadcast();

        // Print summary
        console.log("Factory contract:", address(factory));
        console.log("DAO contract:", address(deployment.dao));
        console.log("");

        console.log("- Multisig plugin:", address(deployment.multisigPlugin));
        console.log("- Emergency multisig plugin:", address(deployment.emergencyMultisigPlugin));
        console.log("- Optimistic token voting plugin:", address(deployment.optimisticTokenVotingPlugin));
        console.log("");

        console.log("- Multisig plugin repository:", address(deployment.multisigPluginRepo));
        console.log("- Emergency multisig plugin repository:", address(deployment.emergencyMultisigPluginRepo));
        console.log("- Optimistic token voting plugin repository:", address(deployment.optimisticTokenVotingPluginRepo));
        console.log("");

        console.log("Public key registry", address(deployment.publicKeyRegistry));
    }

    function getMainnetSettings() internal view returns (TaikoDaoFactory.DeploymentSettings memory settings) {
        settings = TaikoDaoFactory.DeploymentSettings({
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
            osxDaoFactory: vm.envAddress("DAO_FACTORY"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY")),
            // Plugin setup's
            multisigPluginSetup: MultisigPluginSetup(multisigPluginSetup),
            emergencyMultisigPluginSetup: EmergencyMultisigPluginSetup(emergencyMultisigPluginSetup),
            optimisticTokenVotingPluginSetup: OptimisticTokenVotingPluginSetup(optimisticTokenVotingPluginSetup),
            // Multisig members
            multisigMembers: readMultisigMembers(),
            // ENS
            stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
            emergencyMultisigEnsDomain: vm.envString("EMERGENCY_MULTISIG_ENS_DOMAIN"),
            optimisticTokenVotingEnsDomain: vm.envString("OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN")
        });
    }

    function getTestnetSettings() internal returns (TaikoDaoFactory.DeploymentSettings memory settings) {
        address taikoBridgeAddress = vm.addr(vm.envUint("DEPLOYMENT_PRIVATE_KEY")); // Using the deployment wallet for test
        address[] memory multisigMembers = readMultisigMembers();
        address votingToken = createTestToken(multisigMembers, taikoBridgeAddress);

        console.log("Test voting token:", votingToken);
        console.log("");

        settings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: IVotesUpgradeable(votingToken),
            taikoL1ContractAddress: address(new TaikoL1Mock()),
            taikoBridgeAddress: taikoBridgeAddress,
            l2InactivityPeriod: uint64(vm.envUint("L2_INACTIVITY_PERIOD")),
            l2AggregationGracePeriod: uint64(vm.envUint("L2_AGGREGATION_GRACE_PERIOD")),
            // Voting settings
            minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
            minStdProposalDelay: uint64(vm.envUint("MIN_STD_PROPOSAL_DELAY")),
            minStdApprovals: uint16(vm.envUint("MIN_STD_APPROVALS")),
            minEmergencyApprovals: uint16(vm.envUint("MIN_EMERGENCY_APPROVALS")),
            // OSx contracts
            osxDaoFactory: vm.envAddress("DAO_FACTORY"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY")),
            // Plugin setup's
            multisigPluginSetup: MultisigPluginSetup(multisigPluginSetup),
            emergencyMultisigPluginSetup: EmergencyMultisigPluginSetup(emergencyMultisigPluginSetup),
            optimisticTokenVotingPluginSetup: OptimisticTokenVotingPluginSetup(optimisticTokenVotingPluginSetup),
            // Multisig members
            multisigMembers: multisigMembers,
            // ENS
            stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
            emergencyMultisigEnsDomain: vm.envString("EMERGENCY_MULTISIG_ENS_DOMAIN"),
            optimisticTokenVotingEnsDomain: vm.envString("OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN")
        });
    }

    function readMultisigMembers() internal view returns (address[] memory) {
        // JSON list of members
        string memory path = string.concat(vm.projectRoot(), "/script/multisig-members.json");
        string memory json = vm.readFile(path);
        return vm.parseJsonAddressArray(json, "$.members");
    }

    function createTestToken(address[] memory members, address taikoBridge) internal returns (address) {
        address[] memory allTokenHolders = new address[](members.length + 1);
        for (uint256 i = 0; i < members.length; i++) {
            allTokenHolders[i] = members[i];
        }
        allTokenHolders[members.length] = taikoBridge;

        GovernanceERC20Mock testToken = new GovernanceERC20Mock(address(0));
        console.log("Minting test tokens for the multisig members and the bridge");
        testToken.mintAndDelegate(allTokenHolders, 10 ether);

        return address(testToken);
    }
}
