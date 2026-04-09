// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {ScriptBase} from "../lib/ScriptBase.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {TaikoDaoFactory} from "../../src/factory/TaikoDaoFactory.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {MultisigPluginSetup} from "../../src/setup/MultisigPluginSetup.sol";
import {EmergencyMultisigPluginSetup} from "../../src/setup/EmergencyMultisigPluginSetup.sol";
import {OptimisticTokenVotingPluginSetup} from "../../src/setup/OptimisticTokenVotingPluginSetup.sol";
import {DelegationWall} from "../../src/DelegationWall.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {L2VetoReceiver} from "../../src/crosschain/L2VetoReceiver.sol";

/// @title DeployL1 (Fresh deploy)
/// @notice Deploys the full DAO + all plugins + L2VetoReceiver on L1.
/// @dev Step 1 of 3. Run against the L1 RPC.
contract DeployL1 is ScriptBase {
    MultisigPluginSetup multisigPluginSetup;
    EmergencyMultisigPluginSetup emergencyMultisigPluginSetup;
    OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup;

    error EmptyMultisig();

    function run() external {
        // ── ENV VARS ────────────────────────────────────────────
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        address governanceERC20Base = vm.envAddress("GOVERNANCE_ERC20_BASE");
        address governanceWrappedERC20Base = vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE");
        address l1TaikoBridge = vm.envAddress("L1_TAIKO_BRIDGE");
        uint64 l2ChainId = uint64(vm.envUint("L2_CHAIN_ID"));

        // ── DEPLOY ──────────────────────────────────────────────
        vm.startBroadcast(privKey);

        // NOTE: Deploying the plugin setup's separately because of the code size limit
        //       EncryptionRegistry and DelegationWall are deployed by the TaikoDaoFactory
        multisigPluginSetup = new MultisigPluginSetup();
        emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        optimisticTokenVotingPluginSetup = new OptimisticTokenVotingPluginSetup(
            GovernanceERC20(governanceERC20Base), GovernanceWrappedERC20(governanceWrappedERC20Base)
        );

        console.log("Chain ID:", block.chainid);

        TaikoDaoFactory.DeploymentSettings memory settings = _getSettings();

        TaikoDaoFactory factory = new TaikoDaoFactory(settings);
        factory.deployOnce();

        address delegationWall = address(new DelegationWall());

        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();
        L2VetoReceiver receiver = new L2VetoReceiver(
            IDAO(address(deployment.dao)),
            l1TaikoBridge,
            l2ChainId,
            address(deployment.optimisticTokenVotingPlugin)
        );

        vm.stopBroadcast();

        _printSummary(factory, delegationWall, address(receiver));

        string memory key = "l1";
        vm.serializeAddress(key, "factory", address(factory));
        vm.serializeAddress(key, "dao", address(deployment.dao));
        vm.serializeAddress(key, "multisigPlugin", address(deployment.multisigPlugin));
        vm.serializeAddress(key, "emergencyMultisigPlugin", address(deployment.emergencyMultisigPlugin));
        vm.serializeAddress(key, "optimisticTokenVotingPlugin", address(deployment.optimisticTokenVotingPlugin));
        vm.serializeAddress(key, "signerList", address(deployment.signerList));
        vm.serializeAddress(key, "encryptionRegistry", address(deployment.encryptionRegistry));
        vm.serializeAddress(key, "multisigPluginRepo", address(deployment.multisigPluginRepo));
        vm.serializeAddress(key, "emergencyMultisigPluginRepo", address(deployment.emergencyMultisigPluginRepo));
        vm.serializeAddress(key, "optimisticTokenVotingPluginRepo", address(deployment.optimisticTokenVotingPluginRepo));
        vm.serializeAddress(key, "delegationWall", delegationWall);
        string memory json = vm.serializeAddress(key, "vetoReceiver", address(receiver));
        _writeDeployment("deploy/01-DeployL1.s.sol", json);

        console.log("");
        console.log("Next: run 02-DeployL2.s.sol against L2 RPC");
    }

    function _getSettings() internal view returns (TaikoDaoFactory.DeploymentSettings memory settings) {
        settings = TaikoDaoFactory.DeploymentSettings({
            tokenAddress: IVotesUpgradeable(vm.envAddress("L1_VOTING_TOKEN")),
            taikoL1ContractAddress: vm.envAddress("TAIKO_L1_ADDRESS"),
            taikoERC20VaultAddress: vm.envAddress("TAIKO_ERC20_VAULT_ADDRESS"),
            timelockPeriod: uint32(vm.envUint("TIME_LOCK_PERIOD")),
            l2InactivityPeriod: uint32(vm.envUint("L2_INACTIVITY_PERIOD")),
            l2AggregationGracePeriod: uint32(vm.envUint("L2_AGGREGATION_GRACE_PERIOD")),
            skipL2: bool(vm.envBool("SKIP_L2")),
            minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
            minStdProposalDuration: uint32(vm.envUint("MIN_STD_PROPOSAL_DURATION")),
            minStdApprovals: uint16(vm.envUint("MIN_STD_APPROVALS")),
            minEmergencyApprovals: uint16(vm.envUint("MIN_EMERGENCY_APPROVALS")),
            osxDaoFactory: vm.envAddress("DAO_FACTORY_ADDRESS"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY_ADDRESS")),
            multisigPluginSetup: MultisigPluginSetup(multisigPluginSetup),
            emergencyMultisigPluginSetup: EmergencyMultisigPluginSetup(emergencyMultisigPluginSetup),
            optimisticTokenVotingPluginSetup: OptimisticTokenVotingPluginSetup(optimisticTokenVotingPluginSetup),
            multisigMembers: _readMultisigMembers(),
            multisigExpirationPeriod: uint32(vm.envUint("MULTISIG_PROPOSAL_EXPIRATION_PERIOD")),
            stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
            emergencyMultisigEnsDomain: vm.envString("EMERGENCY_MULTISIG_ENS_DOMAIN"),
            optimisticTokenVotingEnsDomain: vm.envString("OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN")
        });
    }

    function _printSummary(TaikoDaoFactory _factory, address _delegationWall, address _receiver) internal view {
        TaikoDaoFactory.DeploymentSettings memory settings = _factory.getSettings();
        TaikoDaoFactory.Deployment memory d = _factory.getDeployment();

        console.log("");
        console.log("Factory:", address(_factory));
        console.log("DAO:", address(d.dao));
        console.log("Voting token:", address(settings.tokenAddress));
        console.log("Taiko ERC20Vault:", settings.taikoERC20VaultAddress);
        console.log("");
        console.log("Plugins");
        console.log("- Multisig:", address(d.multisigPlugin));
        console.log("- Emergency multisig:", address(d.emergencyMultisigPlugin));
        console.log("- Optimistic token voting:", address(d.optimisticTokenVotingPlugin));
        console.log("");
        console.log("Helpers");
        console.log("- Signer list:", address(d.signerList));
        console.log("- Encryption registry:", address(d.encryptionRegistry));
        console.log("- Delegation wall:", _delegationWall);
        console.log("- L2 veto receiver:", _receiver);
        console.log("");
        console.log("Plugin repositories");
        console.log("- Multisig:", address(d.multisigPluginRepo));
        console.log("- Emergency multisig:", address(d.emergencyMultisigPluginRepo));
        console.log("- Optimistic token voting:", address(d.optimisticTokenVotingPluginRepo));
    }

    function _readMultisigMembers() internal view returns (address[] memory result) {
        string memory membersFilePath = vm.envString("MULTISIG_MEMBERS_JSON_FILE_NAME");
        string memory path = string.concat(vm.projectRoot(), membersFilePath);
        string memory strJson = vm.readFile(path);

        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) revert EmptyMultisig();

        result = vm.parseJsonAddressArray(strJson, "$.members");
        if (result.length == 0) revert EmptyMultisig();
    }
}
