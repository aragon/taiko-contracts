// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {TaikoDaoFactory} from "../src/factory/TaikoDaoFactory.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {MultisigPluginSetup} from "../src/setup/MultisigPluginSetup.sol";
import {EmergencyMultisigPluginSetup} from "../src/setup/EmergencyMultisigPluginSetup.sol";
import {OptimisticTokenVotingPluginSetup} from "../src/setup/OptimisticTokenVotingPluginSetup.sol";
import {DelegationWall} from "../src/DelegationWall.sol";
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

        // NOTE: Deploying the plugin setup's separately because of the code size limit
        //       PublicKeyRegistry and DelegationWall are deployed by the TaikoDaoFactory

        // Deploy the plugin setup's
        multisigPluginSetup = new MultisigPluginSetup();
        emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        optimisticTokenVotingPluginSetup = new OptimisticTokenVotingPluginSetup(
            GovernanceERC20(vm.envAddress("GOVERNANCE_ERC20_BASE")),
            GovernanceWrappedERC20(vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE"))
        );

        console.log("Chain ID:", block.chainid);
        console.log("Deploying from:", vm.addr(vm.envUint("DEPLOYMENT_PRIVATE_KEY")));

        TaikoDaoFactory.DeploymentSettings memory settings;
        if (vm.envBool("DEPLOY_AS_PRODUCTION")) {
            settings = getProductionSettings();
        } else {
            settings = getInternalTestingSettings();
        }

        console.log("");

        TaikoDaoFactory factory = new TaikoDaoFactory(settings);
        factory.deployOnce();
        TaikoDaoFactory.Deployment memory daoDeployment = factory.getDeployment();
        address delegationWall = address(new DelegationWall());

        vm.stopBroadcast();

        // Print summary
        console.log("Factory:", address(factory));
        console.log("");
        console.log("DAO:", address(daoDeployment.dao));
        console.log("Voting token:", address(settings.tokenAddress));
        console.log("Taiko Bridge:", settings.taikoBridgeAddress);
        console.log("");

        console.log("Plugins");
        console.log("- Multisig plugin:", address(daoDeployment.multisigPlugin));
        console.log("- Emergency multisig plugin:", address(daoDeployment.emergencyMultisigPlugin));
        console.log("- Optimistic token voting plugin:", address(daoDeployment.optimisticTokenVotingPlugin));
        console.log("");

        console.log("Plugin repositories");
        console.log("- Multisig plugin repository:", address(daoDeployment.multisigPluginRepo));
        console.log("- Emergency multisig plugin repository:", address(daoDeployment.emergencyMultisigPluginRepo));
        console.log(
            "- Optimistic token voting plugin repository:", address(daoDeployment.optimisticTokenVotingPluginRepo)
        );
        console.log("");

        console.log("Helpers");
        console.log("- Public key registry", address(daoDeployment.publicKeyRegistry));
        console.log("- Delegation wall", address(delegationWall));
    }

    function getProductionSettings() internal view returns (TaikoDaoFactory.DeploymentSettings memory settings) {
        console.log("Using production settings");

        settings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: IVotesUpgradeable(vm.envAddress("TOKEN_ADDRESS")),
            taikoL1ContractAddress: vm.envAddress("TAIKO_L1_ADDRESS"),
            taikoBridgeAddress: vm.envAddress("TAIKO_BRIDGE_ADDRESS"),
            l2InactivityPeriod: uint64(vm.envUint("L2_INACTIVITY_PERIOD")),
            l2AggregationGracePeriod: uint64(vm.envUint("L2_AGGREGATION_GRACE_PERIOD")),
            skipL2: bool(vm.envBool("SKIP_L2")),
            // Voting settings
            minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
            minStdProposalDuration: uint64(vm.envUint("MIN_STD_PROPOSAL_DURATION")),
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
            multisigExpirationPeriod: uint64(vm.envUint("MULTISIG_PROPOSAL_EXPIRATION_PERIOD")),
            // ENS
            stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
            emergencyMultisigEnsDomain: vm.envString("EMERGENCY_MULTISIG_ENS_DOMAIN"),
            optimisticTokenVotingEnsDomain: vm.envString("OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN")
        });
    }

    function getInternalTestingSettings() internal returns (TaikoDaoFactory.DeploymentSettings memory settings) {
        console.log("Using internal testing settings");

        address taikoBridgeAddress = address(0x1234567890);
        address[] memory multisigMembers = readMultisigMembers();
        address votingToken = createTestToken(multisigMembers, taikoBridgeAddress);

        settings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: IVotesUpgradeable(votingToken),
            taikoL1ContractAddress: address(new TaikoL1Mock()),
            taikoBridgeAddress: taikoBridgeAddress,
            l2InactivityPeriod: uint64(vm.envUint("L2_INACTIVITY_PERIOD")),
            l2AggregationGracePeriod: uint64(vm.envUint("L2_AGGREGATION_GRACE_PERIOD")),
            skipL2: bool(vm.envBool("SKIP_L2")),
            // Voting settings
            minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
            minStdProposalDuration: uint64(vm.envUint("MIN_STD_PROPOSAL_DURATION")),
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
            multisigExpirationPeriod: uint64(vm.envUint("MULTISIG_PROPOSAL_EXPIRATION_PERIOD")),
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
