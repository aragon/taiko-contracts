// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {ScriptBase} from "./lib/ScriptBase.sol";
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
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {L2VetoReceiver} from "../src/crosschain/L2VetoReceiver.sol";
import {L2VetoAggregator} from "../src/crosschain/L2VetoAggregator.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";

contract Deploy is ScriptBase {
    MultisigPluginSetup multisigPluginSetup;
    EmergencyMultisigPluginSetup emergencyMultisigPluginSetup;
    OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup;

    /// @dev Thrown when attempting to deploy a multisig with no members
    error EmptyMultisig();

    function run() public {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        bool skipL2 = vm.envOr("SKIP_L2", false);

        // ── DEPLOY ON L1 ────────────────────────────────────────
        vm.createSelectFork(vm.envString("L1_CHAIN"));

        (TaikoDaoFactory factory, address delegationWall, L2VetoReceiver receiver) = _deployL1(privKey);
        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();

        printDeploymentSummary(factory, delegationWall, address(receiver));

        if (skipL2) {
            console.log("");
            console.log("SKIP_L2=true - skipping L2 deployment and proposal generation");
            return;
        }

        // ── DEPLOY ON L2 ────────────────────────────────────────
        vm.createSelectFork(vm.envString("L2_CHAIN"));

        L2VetoAggregator aggregator = _deployL2(privKey, address(receiver));

        // ── GENERATE CONFIGURE PROPOSAL ─────────────────────────
        // Switch back to L1 to read on-chain permission constants
        vm.createSelectFork(vm.envString("L1_CHAIN"));

        _writeConfigureProposal(deployment, receiver, aggregator);

        console.log("");
        console.log("Next step: submit proposals/proposal-configure-l2-veto.json to the DAO");
    }

    function _deployL1(uint256 _privKey)
        internal
        returns (TaikoDaoFactory factory, address delegationWall, L2VetoReceiver receiver)
    {
        vm.startBroadcast(_privKey);

        // NOTE: Deploying the plugin setup's separately because of the code size limit
        //       EncryptionRegistry and DelegationWall are deployed by the TaikoDaoFactory
        multisigPluginSetup = new MultisigPluginSetup();
        emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        optimisticTokenVotingPluginSetup = new OptimisticTokenVotingPluginSetup(
            GovernanceERC20(vm.envAddress("GOVERNANCE_ERC20_BASE")),
            GovernanceWrappedERC20(vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE"))
        );

        console.log("Chain ID:", block.chainid);

        TaikoDaoFactory.DeploymentSettings memory settings;
        if (vm.envOr("MINT_TEST_TOKENS", false)) {
            settings = getTestTokenSettings();
        } else {
            settings = getProductionSettings();
        }

        console.log("");

        factory = new TaikoDaoFactory(settings);
        factory.deployOnce();

        delegationWall = address(new DelegationWall());

        // Deploy L2VetoReceiver
        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();
        receiver = new L2VetoReceiver(
            IDAO(address(deployment.dao)),
            vm.envAddress("L1_TAIKO_BRIDGE"),
            uint64(vm.envUint("L2_CHAIN_ID")),
            address(deployment.optimisticTokenVotingPlugin)
        );

        vm.stopBroadcast();
    }

    function _deployL2(uint256 _privKey, address _receiver) internal returns (L2VetoAggregator aggregator) {
        vm.startBroadcast(_privKey);

        aggregator = new L2VetoAggregator(
            vm.envAddress("L2_TAIKO_BRIDGE"),
            uint64(vm.envUint("L1_CHAIN_ID")),
            vm.envAddress("L2_VOTING_TOKEN"),
            _receiver
        );
        console.log("L2VetoAggregator (L2):", address(aggregator));

        vm.stopBroadcast();
    }

    function _writeConfigureProposal(
        TaikoDaoFactory.Deployment memory _deployment,
        L2VetoReceiver _receiver,
        L2VetoAggregator _aggregator
    ) internal {
        address dao = address(_deployment.dao);
        address plugin = address(_deployment.optimisticTokenVotingPlugin);

        bytes32 setAggregatorPermission = _receiver.SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID();

        IDAO.Action[] memory actions = new IDAO.Action[](3);
        actions[0] = IDAO.Action({
            to: dao,
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (address(_receiver), dao, setAggregatorPermission))
        });
        actions[1] = IDAO.Action({
            to: plugin,
            value: 0,
            data: abi.encodeCall(OptimisticTokenVotingPlugin.setL2VetoReceiver, (address(_receiver)))
        });
        actions[2] = IDAO.Action({
            to: address(_receiver),
            value: 0,
            data: abi.encodeCall(L2VetoReceiver.setTrustedL2Aggregator, (address(_aggregator)))
        });

        _writeProposal("proposal-configure-l2-veto.json", actions);
        _logActions(actions);
    }


    function getProductionSettings() internal view returns (TaikoDaoFactory.DeploymentSettings memory settings) {
        console.log("Using production settings");

        settings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: IVotesUpgradeable(vm.envAddress("L1_VOTING_TOKEN")),
            taikoL1ContractAddress: vm.envAddress("TAIKO_L1_ADDRESS"),
            taikoERC20VaultAddress: vm.envAddress("TAIKO_ERC20_VAULT_ADDRESS"),
            timelockPeriod: uint32(vm.envUint("TIME_LOCK_PERIOD")),
            l2InactivityPeriod: uint32(vm.envUint("L2_INACTIVITY_PERIOD")),
            l2AggregationGracePeriod: uint32(vm.envUint("L2_AGGREGATION_GRACE_PERIOD")),
            skipL2: bool(vm.envBool("SKIP_L2")),
            // Voting settings
            minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
            minStdProposalDuration: uint32(vm.envUint("MIN_STD_PROPOSAL_DURATION")),
            minStdApprovals: uint16(vm.envUint("MIN_STD_APPROVALS")),
            minEmergencyApprovals: uint16(vm.envUint("MIN_EMERGENCY_APPROVALS")),
            // OSx contracts
            osxDaoFactory: vm.envAddress("DAO_FACTORY_ADDRESS"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY_ADDRESS")),
            // Plugin setup's
            multisigPluginSetup: MultisigPluginSetup(multisigPluginSetup),
            emergencyMultisigPluginSetup: EmergencyMultisigPluginSetup(emergencyMultisigPluginSetup),
            optimisticTokenVotingPluginSetup: OptimisticTokenVotingPluginSetup(optimisticTokenVotingPluginSetup),
            // Multisig members
            multisigMembers: readMultisigMembers(),
            multisigExpirationPeriod: uint32(vm.envUint("MULTISIG_PROPOSAL_EXPIRATION_PERIOD")),
            // ENS
            stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
            emergencyMultisigEnsDomain: vm.envString("EMERGENCY_MULTISIG_ENS_DOMAIN"),
            optimisticTokenVotingEnsDomain: vm.envString("OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN")
        });
    }

    function getTestTokenSettings() internal returns (TaikoDaoFactory.DeploymentSettings memory settings) {
        console.log("Using test token settings");

        address taikoERC20VaultAddress = vm.envAddress("TAIKO_ERC20_VAULT_ADDRESS");
        address[] memory multisigMembers = readMultisigMembers();
        address votingToken = createTestToken(multisigMembers, taikoERC20VaultAddress);

        settings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: IVotesUpgradeable(votingToken),
            taikoL1ContractAddress: address(new TaikoL1Mock()),
            taikoERC20VaultAddress: taikoERC20VaultAddress,
            timelockPeriod: uint32(vm.envUint("TIME_LOCK_PERIOD")),
            l2InactivityPeriod: uint32(vm.envUint("L2_INACTIVITY_PERIOD")),
            l2AggregationGracePeriod: uint32(vm.envUint("L2_AGGREGATION_GRACE_PERIOD")),
            skipL2: bool(vm.envBool("SKIP_L2")),
            // Voting settings
            minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
            minStdProposalDuration: uint32(vm.envUint("MIN_STD_PROPOSAL_DURATION")),
            minStdApprovals: uint16(vm.envUint("MIN_STD_APPROVALS")),
            minEmergencyApprovals: uint16(vm.envUint("MIN_EMERGENCY_APPROVALS")),
            // OSx contracts
            osxDaoFactory: vm.envAddress("DAO_FACTORY_ADDRESS"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY_ADDRESS")),
            // Plugin setup's
            multisigPluginSetup: MultisigPluginSetup(multisigPluginSetup),
            emergencyMultisigPluginSetup: EmergencyMultisigPluginSetup(emergencyMultisigPluginSetup),
            optimisticTokenVotingPluginSetup: OptimisticTokenVotingPluginSetup(optimisticTokenVotingPluginSetup),
            // Multisig members
            multisigMembers: multisigMembers,
            multisigExpirationPeriod: uint32(vm.envUint("MULTISIG_PROPOSAL_EXPIRATION_PERIOD")),
            // ENS
            stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
            emergencyMultisigEnsDomain: vm.envString("EMERGENCY_MULTISIG_ENS_DOMAIN"),
            optimisticTokenVotingEnsDomain: vm.envString("OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN")
        });
    }

    function printDeploymentSummary(TaikoDaoFactory factory, address delegationWall, address l2VetoReceiver) internal view {
        TaikoDaoFactory.DeploymentSettings memory settings = factory.getSettings();
        TaikoDaoFactory.Deployment memory daoDeployment = factory.getDeployment();

        console.log("Factory:", address(factory));
        console.log("");
        console.log("DAO:", address(daoDeployment.dao));
        console.log("Voting token:", address(settings.tokenAddress));
        console.log("Taiko ERC20Vault:", settings.taikoERC20VaultAddress);
        console.log("");

        console.log("Plugins");
        console.log("- Multisig plugin:", address(daoDeployment.multisigPlugin));
        console.log("- Emergency multisig plugin:", address(daoDeployment.emergencyMultisigPlugin));
        console.log("- Optimistic token voting plugin:", address(daoDeployment.optimisticTokenVotingPlugin));
        console.log("");

        console.log("Helpers");
        console.log("- Signer list", address(daoDeployment.signerList));
        console.log("- Encryption registry", address(daoDeployment.encryptionRegistry));
        console.log("- Delegation wall", address(delegationWall));
        console.log("- L2 veto receiver", l2VetoReceiver);

        console.log("");

        console.log("Plugin repositories");
        console.log("- Multisig plugin repository:", address(daoDeployment.multisigPluginRepo));
        console.log("- Emergency multisig plugin repository:", address(daoDeployment.emergencyMultisigPluginRepo));
        console.log(
            "- Optimistic token voting plugin repository:", address(daoDeployment.optimisticTokenVotingPluginRepo)
        );
    }

    function readMultisigMembers() public view returns (address[] memory result) {
        // JSON list of members
        string memory membersFilePath = vm.envString("MULTISIG_MEMBERS_JSON_FILE_NAME");
        string memory path = string.concat(vm.projectRoot(), membersFilePath);
        string memory strJson = vm.readFile(path);

        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) revert EmptyMultisig();

        result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) revert EmptyMultisig();
    }

    function createTestToken(address[] memory members, address taikoERC20Vault) internal returns (address) {
        address[] memory allTokenHolders = new address[](members.length + 1);
        for (uint256 i = 0; i < members.length; i++) {
            allTokenHolders[i] = members[i];
        }
        allTokenHolders[members.length] = taikoERC20Vault;

        GovernanceERC20Mock testToken = new GovernanceERC20Mock(address(0));
        console.log("Minting test tokens for the multisig members and the ERC20Vault");
        testToken.mintAndDelegate(allTokenHolders, 10 ether);

        return address(testToken);
    }
}
