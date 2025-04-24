// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "../base/AragonTest.sol";
import {TaikoDaoFactory} from "../../src/factory/TaikoDaoFactory.sol";
import {GovernanceERC20Mock} from "../mocks/GovernanceERC20Mock.sol";
import {MockPluginSetupProcessor} from "../mocks/osx/MockPSP.sol";
import {MockPluginRepoRegistry} from "../mocks/osx/MockPluginRepoRegistry.sol";
import {MockDaoFactory} from "../mocks/osx/MockDaoFactory.sol";
import {TaikoL1Mock} from "../mocks/TaikoL1Mock.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {createProxyAndCall} from "../../src/helpers/proxy.sol";
import {MultisigPluginSetup} from "../../src/setup/MultisigPluginSetup.sol";
import {EmergencyMultisigPluginSetup} from "../../src/setup/EmergencyMultisigPluginSetup.sol";
import {OptimisticTokenVotingPluginSetup} from "../../src/setup/OptimisticTokenVotingPluginSetup.sol";
import {SignerList, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID} from "../../src/SignerList.sol";

contract TaikoDaoFactoryTest is AragonTest {
    function test_ShouldStoreTheSettings_1() public {
        DAO tempMgmtDao = DAO(payable(address(0)));
        GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
        TaikoL1Mock taikoL1ContractAddress = new TaikoL1Mock();
        address taikoBridgeAddress = address(0x1234);
        address[] memory multisigMembers = new address[](13);

        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup =
            new OptimisticTokenVotingPluginSetup(GovernanceERC20(address(1)), GovernanceWrappedERC20(address(1)));

        MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
        PluginRepoFactory pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));
        MockPluginSetupProcessor psp = new MockPluginSetupProcessor(new address[](0));
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            excludedVotingPowerHolders: getExcludedVotingPowerHolders(),
            timelockPeriod: 7 days,
            l2InactivityPeriod: 10 minutes, // uint32
            l2AggregationGracePeriod: 2 days, // uint32
            skipL2: false,
            // Voting settings
            minVetoRatio: 200_000, // uint32
            minStdProposalDuration: 10 days, // uint32
            minStdApprovals: 7, // uint16
            minEmergencyApprovals: 11, // uint16
            // OSx contracts
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)), // PluginSetupProcessor
            pluginRepoFactory: PluginRepoFactory(address(pRefoFactory)), // PluginRepoFactory
            // Plugin setup's
            multisigPluginSetup: multisigPluginSetup,
            emergencyMultisigPluginSetup: emergencyMultisigPluginSetup,
            optimisticTokenVotingPluginSetup: optimisticTokenVotingPluginSetup,
            // Multisig
            multisigMembers: multisigMembers, // address[]
            multisigExpirationPeriod: 9 days,
            // ENS
            stdMultisigEnsDomain: "multisig", // string
            emergencyMultisigEnsDomain: "eMultisig", // string
            optimisticTokenVotingEnsDomain: "optimistic" // string
        });

        TaikoDaoFactory factory = new TaikoDaoFactory(creationSettings);

        // Check
        TaikoDaoFactory.DeploymentSettings memory actualSettings = factory.getSettings();
        assertEq(address(actualSettings.tokenAddress), address(creationSettings.tokenAddress), "Incorrect tokenAddress");
        assertEq(
            actualSettings.taikoL1ContractAddress,
            creationSettings.taikoL1ContractAddress,
            "Incorrect taikoL1ContractAddress"
        );
        assertEq(actualSettings.taikoBridgeAddress, creationSettings.taikoBridgeAddress, "Incorrect taikoBridgeAddress");
        assertEq(actualSettings.timelockPeriod, creationSettings.timelockPeriod, "Incorrect timelockPeriod");
        assertEq(actualSettings.l2InactivityPeriod, creationSettings.l2InactivityPeriod, "Incorrect l2InactivityPeriod");
        assertEq(
            actualSettings.l2AggregationGracePeriod,
            creationSettings.l2AggregationGracePeriod,
            "Incorrect l2AggregationGracePeriod"
        );
        assertEq(actualSettings.skipL2, creationSettings.skipL2, "Incorrect skipL2");
        assertEq(actualSettings.minVetoRatio, creationSettings.minVetoRatio, "Incorrect minVetoRatio");
        assertEq(
            actualSettings.minStdProposalDuration,
            creationSettings.minStdProposalDuration,
            "Incorrect minStdProposalDuration"
        );
        assertEq(actualSettings.minStdApprovals, creationSettings.minStdApprovals, "Incorrect minStdApprovals");
        assertEq(
            actualSettings.minEmergencyApprovals,
            creationSettings.minEmergencyApprovals,
            "Incorrect minEmergencyApprovals"
        );
        assertEq(
            address(actualSettings.osxDaoFactory), address(creationSettings.osxDaoFactory), "Incorrect osxDaoFactory"
        );
        assertEq(
            address(actualSettings.pluginSetupProcessor),
            address(creationSettings.pluginSetupProcessor),
            "Incorrect pluginSetupProcessor"
        );
        assertEq(
            address(actualSettings.pluginRepoFactory),
            address(creationSettings.pluginRepoFactory),
            "Incorrect pluginRepoFactory"
        );
        assertEq(
            address(actualSettings.multisigPluginSetup),
            address(creationSettings.multisigPluginSetup),
            "Incorrect multisigPluginSetup"
        );
        assertEq(
            address(actualSettings.emergencyMultisigPluginSetup),
            address(creationSettings.emergencyMultisigPluginSetup),
            "Incorrect emergencyMultisigPluginSetup"
        );
        assertEq(
            address(actualSettings.optimisticTokenVotingPluginSetup),
            address(creationSettings.optimisticTokenVotingPluginSetup),
            "Incorrect optimisticTokenVotingPluginSetup"
        );
        assertEq(
            actualSettings.multisigMembers.length,
            creationSettings.multisigMembers.length,
            "Incorrect multisigMembers.length"
        );
        assertEq(
            actualSettings.multisigExpirationPeriod,
            creationSettings.multisigExpirationPeriod,
            "Incorrect multisigExpirationPeriod"
        );
        assertEq(
            actualSettings.stdMultisigEnsDomain, creationSettings.stdMultisigEnsDomain, "Incorrect stdMultisigEnsDomain"
        );
        assertEq(
            actualSettings.emergencyMultisigEnsDomain,
            creationSettings.emergencyMultisigEnsDomain,
            "Incorrect emergencyMultisigEnsDomain"
        );
        assertEq(
            actualSettings.optimisticTokenVotingEnsDomain,
            creationSettings.optimisticTokenVotingEnsDomain,
            "Incorrect optimisticTokenVotingEnsDomain"
        );
    }

    function test_ShouldStoreTheSettings_2() public {
        DAO tempMgmtDao = DAO(payable(address(0)));
        GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
        TaikoL1Mock taikoL1ContractAddress = new TaikoL1Mock();
        address taikoBridgeAddress = address(0x1234);
        address[] memory multisigMembers = new address[](15);

        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup =
            new OptimisticTokenVotingPluginSetup(GovernanceERC20(address(1)), GovernanceWrappedERC20(address(1)));

        MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
        PluginRepoFactory pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));
        MockPluginSetupProcessor psp = new MockPluginSetupProcessor(new address[](0));
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            excludedVotingPowerHolders: getExcludedVotingPowerHolders(),
            timelockPeriod: 14 days,
            l2InactivityPeriod: 27 minutes, // uint32
            l2AggregationGracePeriod: 77 days, // uint32
            skipL2: false,
            // Voting settings
            minVetoRatio: 456_000, // uint32
            minStdProposalDuration: 14 days, // uint32
            minStdApprovals: 4, // uint16
            minEmergencyApprovals: 27, // uint16
            // OSx contracts
            osxDaoFactory: address(daoFactory), // DaoFactory
            pluginSetupProcessor: PluginSetupProcessor(address(psp)), // PluginSetupProcessor
            pluginRepoFactory: PluginRepoFactory(address(pRefoFactory)), // PluginRepoFactory
            // Plugin setup's
            multisigPluginSetup: multisigPluginSetup,
            emergencyMultisigPluginSetup: emergencyMultisigPluginSetup,
            optimisticTokenVotingPluginSetup: optimisticTokenVotingPluginSetup,
            // Multisig
            multisigMembers: multisigMembers, // address[]
            multisigExpirationPeriod: 4 days,
            // ENS
            stdMultisigEnsDomain: "multisig-1234", // string
            emergencyMultisigEnsDomain: "eMultisig-1234", // string
            optimisticTokenVotingEnsDomain: "optimistic-1234" // string
        });

        TaikoDaoFactory factory = new TaikoDaoFactory(creationSettings);

        // Check
        TaikoDaoFactory.DeploymentSettings memory actualSettings = factory.getSettings();
        assertEq(address(actualSettings.tokenAddress), address(creationSettings.tokenAddress), "Incorrect tokenAddress");
        assertEq(
            actualSettings.taikoL1ContractAddress,
            creationSettings.taikoL1ContractAddress,
            "Incorrect taikoL1ContractAddress"
        );
        assertEq(actualSettings.taikoBridgeAddress, creationSettings.taikoBridgeAddress, "Incorrect taikoBridgeAddress");
        assertEq(actualSettings.timelockPeriod, creationSettings.timelockPeriod, "Incorrect timelockPeriod");
        assertEq(actualSettings.l2InactivityPeriod, creationSettings.l2InactivityPeriod, "Incorrect l2InactivityPeriod");
        assertEq(
            actualSettings.l2AggregationGracePeriod,
            creationSettings.l2AggregationGracePeriod,
            "Incorrect l2AggregationGracePeriod"
        );
        assertEq(actualSettings.skipL2, creationSettings.skipL2, "Incorrect skipL2");
        assertEq(actualSettings.minVetoRatio, creationSettings.minVetoRatio, "Incorrect minVetoRatio");
        assertEq(
            actualSettings.minStdProposalDuration,
            creationSettings.minStdProposalDuration,
            "Incorrect minStdProposalDuration"
        );
        assertEq(actualSettings.minStdApprovals, creationSettings.minStdApprovals, "Incorrect minStdApprovals");
        assertEq(
            actualSettings.minEmergencyApprovals,
            creationSettings.minEmergencyApprovals,
            "Incorrect minEmergencyApprovals"
        );
        assertEq(
            address(actualSettings.osxDaoFactory), address(creationSettings.osxDaoFactory), "Incorrect osxDaoFactory"
        );
        assertEq(
            address(actualSettings.pluginSetupProcessor),
            address(creationSettings.pluginSetupProcessor),
            "Incorrect pluginSetupProcessor"
        );
        assertEq(
            address(actualSettings.pluginRepoFactory),
            address(creationSettings.pluginRepoFactory),
            "Incorrect pluginRepoFactory"
        );
        assertEq(
            address(actualSettings.multisigPluginSetup),
            address(creationSettings.multisigPluginSetup),
            "Incorrect multisigPluginSetup"
        );
        assertEq(
            address(actualSettings.emergencyMultisigPluginSetup),
            address(creationSettings.emergencyMultisigPluginSetup),
            "Incorrect emergencyMultisigPluginSetup"
        );
        assertEq(
            address(actualSettings.optimisticTokenVotingPluginSetup),
            address(creationSettings.optimisticTokenVotingPluginSetup),
            "Incorrect optimisticTokenVotingPluginSetup"
        );
        assertEq(
            actualSettings.multisigMembers.length,
            creationSettings.multisigMembers.length,
            "Incorrect multisigMembers.length"
        );
        assertEq(
            actualSettings.multisigExpirationPeriod,
            creationSettings.multisigExpirationPeriod,
            "Incorrect multisigExpirationPeriod"
        );
        assertEq(
            actualSettings.stdMultisigEnsDomain, creationSettings.stdMultisigEnsDomain, "Incorrect stdMultisigEnsDomain"
        );
        assertEq(
            actualSettings.emergencyMultisigEnsDomain,
            creationSettings.emergencyMultisigEnsDomain,
            "Incorrect emergencyMultisigEnsDomain"
        );
        assertEq(
            actualSettings.optimisticTokenVotingEnsDomain,
            creationSettings.optimisticTokenVotingEnsDomain,
            "Incorrect optimisticTokenVotingEnsDomain"
        );
    }

    function test_StandardDeployment_1() public {
        DAO tempMgmtDao = DAO(
            payable(
                createProxyAndCall(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
        TaikoL1Mock taikoL1ContractAddress = new TaikoL1Mock();
        address taikoBridgeAddress = address(0x1234);
        address[] memory multisigMembers = new address[](13);
        for (uint256 i = 0; i < 13; i++) {
            multisigMembers[i] = address(uint160(i + 1));
        }

        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: new address[](0), amounts: new uint256[](0)});
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup = new OptimisticTokenVotingPluginSetup(
            new GovernanceERC20(tempMgmtDao, "", "", mintSettings), new GovernanceWrappedERC20(tokenAddress, "", "")
        );

        PluginRepoFactory pRefoFactory;
        MockPluginSetupProcessor psp;
        {
            MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
            pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));

            address[] memory setups = new address[](3);
            // adding in reverse order (stack)
            setups[2] = address(multisigPluginSetup);
            setups[1] = address(emergencyMultisigPluginSetup);
            setups[0] = address(optimisticTokenVotingPluginSetup);
            psp = new MockPluginSetupProcessor(setups);
        }
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            excludedVotingPowerHolders: getExcludedVotingPowerHolders(),
            timelockPeriod: 20 days,
            l2InactivityPeriod: 10 minutes, // uint32
            l2AggregationGracePeriod: 2 days, // uint32
            skipL2: false,
            // Voting settings
            minVetoRatio: 200_000, // uint32
            minStdProposalDuration: 10 days, // uint32
            minStdApprovals: 7, // uint16
            minEmergencyApprovals: 11, // uint16
            // OSx contracts
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)), // PluginSetupProcessor
            pluginRepoFactory: PluginRepoFactory(address(pRefoFactory)), // PluginRepoFactory
            // Plugin setup's
            multisigPluginSetup: multisigPluginSetup,
            emergencyMultisigPluginSetup: emergencyMultisigPluginSetup,
            optimisticTokenVotingPluginSetup: optimisticTokenVotingPluginSetup,
            // Multisig
            multisigMembers: multisigMembers, // address[]
            multisigExpirationPeriod: 15 days,
            // ENS
            stdMultisigEnsDomain: "multisig", // string
            emergencyMultisigEnsDomain: "eMultisig", // string
            optimisticTokenVotingEnsDomain: "optimistic" // string
        });

        // Deploy
        TaikoDaoFactory factory = new TaikoDaoFactory(creationSettings);

        factory.deployOnce();
        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();

        vm.roll(block.number + 1); // mint one block

        // DAO checks

        assertNotEq(address(deployment.dao), address(0), "Empty DAO field");
        assertEq(deployment.dao.daoURI(), "", "DAO URI should be empty");
        assertEq(address(deployment.dao.signatureValidator()), address(0), "signatureValidator should be empty");
        assertEq(address(deployment.dao.getTrustedForwarder()), address(0), "trustedForwarder should be empty");
        assertEq(
            deployment.dao.hasPermission(
                address(deployment.dao), address(deployment.dao), deployment.dao.ROOT_PERMISSION_ID(), bytes("")
            ),
            true,
            "The DAO should be ROOT on itself"
        );
        assertEq(
            deployment.dao.hasPermission(
                address(deployment.dao), address(deployment.dao), deployment.dao.UPGRADE_DAO_PERMISSION_ID(), bytes("")
            ),
            true,
            "The DAO should have UPGRADE_DAO_PERMISSION on itself"
        );
        assertEq(
            deployment.dao.hasPermission(
                address(deployment.dao),
                address(deployment.dao),
                deployment.dao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID(),
                bytes("")
            ),
            true,
            "The DAO should have REGISTER_STANDARD_CALLBACK_PERMISSION_ID on itself"
        );

        // Signer list

        assertEq(deployment.signerList.addresslistLength(), 13, "Invalid addresslistLength");
        for (uint256 i = 0; i < 13; i++) {
            assertEq(deployment.signerList.isListed(multisigMembers[i]), true, "Should be a member");
        }
        for (uint256 i = 14; i < 50; i++) {
            assertEq(deployment.signerList.isListed(address(uint160(i))), false, "Should not be a member");
        }

        // Multisig plugin

        assertNotEq(address(deployment.multisigPlugin), address(0), "Empty multisig field");
        assertEq(
            deployment.multisigPlugin.lastMultisigSettingsChange(),
            block.number - 1,
            "Invalid lastMultisigSettingsChange"
        );
        assertEq(deployment.multisigPlugin.proposalCount(), 0, "Invalid proposal count");

        {
            (
                bool onlyListed,
                uint16 minApprovals,
                uint64 destinationProposalDuration,
                SignerList signerList,
                uint64 expirationPeriod
            ) = deployment.multisigPlugin.multisigSettings();

            assertEq(onlyListed, true, "Invalid onlyListed");
            assertEq(minApprovals, 7, "Invalid minApprovals");
            assertEq(destinationProposalDuration, 10 days, "Invalid destinationProposalDuration");
            assertEq(address(signerList), address(deployment.signerList), "Incorrect signerList");
            assertEq(expirationPeriod, 15 days, "Invalid expirationPeriod");
        }

        // Emergency Multisig plugin

        assertNotEq(address(deployment.emergencyMultisigPlugin), address(0), "Empty emergencyMultisig field");
        assertEq(
            deployment.emergencyMultisigPlugin.lastMultisigSettingsChange(),
            block.number - 1,
            "Invalid lastMultisigSettingsChange"
        );
        assertEq(deployment.emergencyMultisigPlugin.proposalCount(), 0, "Invalid proposal count");
        {
            (bool onlyListed, uint16 minApprovals, Addresslist signerList, uint64 expirationPeriod) =
                deployment.emergencyMultisigPlugin.multisigSettings();

            assertEq(onlyListed, true, "Invalid onlyListed");
            assertEq(minApprovals, 11, "Invalid minApprovals");
            assertEq(address(signerList), address(deployment.signerList), "Invalid signerList");
            assertEq(expirationPeriod, 15 days, "Invalid expirationPeriod");
        }

        // Optimistic token voting plugin checks

        assertNotEq(
            address(deployment.optimisticTokenVotingPlugin), address(0), "Empty optimisticTokenVotingPlugin field"
        );
        assertEq(
            address(deployment.optimisticTokenVotingPlugin.votingToken()), address(tokenAddress), "Invalid votingToken"
        );
        assertEq(
            address(deployment.optimisticTokenVotingPlugin.taikoL1()),
            address(taikoL1ContractAddress),
            "Invalid taikoL1"
        );
        assertEq(
            address(deployment.optimisticTokenVotingPlugin.taikoBridge()),
            address(taikoBridgeAddress),
            "Invalid taikoBridge"
        );
        assertEq(deployment.optimisticTokenVotingPlugin.proposalCount(), 0, "Invalid proposal count");
        {
            (
                uint32 minVetoRatio,
                uint32 minDuration,
                uint32 timelockPeriod,
                uint32 l2InactivityPeriod,
                uint32 l2AggregationGracePeriod,
                bool skipL2
            ) = deployment.optimisticTokenVotingPlugin.governanceSettings();

            assertEq(minVetoRatio, 200_000, "Invalid minVetoRatio");
            assertEq(minDuration, 0, "Invalid minDuration"); // 10 days is enforced on the condition contract
            assertEq(timelockPeriod, 20 days, "Invalid timelockPeriod");
            assertEq(l2InactivityPeriod, 10 minutes, "Invalid l2InactivityPeriod");
            assertEq(l2AggregationGracePeriod, 2 days, "Invalid l2AggregationGracePeriod");
            assertEq(skipL2, false, "Invalid skipL2");
        }

        // PLUGIN REPO's

        PluginRepo.Version memory version;

        // Multisig repo
        assertNotEq(address(deployment.multisigPluginRepo), address(0), "Empty multisigPluginRepo field");
        assertEq(deployment.multisigPluginRepo.latestRelease(), 1, "Invalid latestRelease");
        assertEq(deployment.multisigPluginRepo.buildCount(1), 1, "Invalid buildCount");
        version = deployment.multisigPluginRepo.getLatestVersion(1);
        assertEq(address(version.pluginSetup), address(multisigPluginSetup), "Invalid multisigPluginSetup");

        // Emergency multisig repo
        assertNotEq(
            address(deployment.emergencyMultisigPluginRepo), address(0), "Empty emergencyMultisigPluginRepo field"
        );
        assertEq(deployment.emergencyMultisigPluginRepo.latestRelease(), 1, "Invalid latestRelease");
        assertEq(deployment.emergencyMultisigPluginRepo.buildCount(1), 1, "Invalid buildCount");
        version = deployment.emergencyMultisigPluginRepo.getLatestVersion(1);
        assertEq(
            address(version.pluginSetup), address(emergencyMultisigPluginSetup), "Invalid emergencyMultisigPluginSetup"
        );

        // Optimistic repo
        assertNotEq(
            address(deployment.optimisticTokenVotingPluginRepo),
            address(0),
            "Empty optimisticTokenVotingPluginRepo field"
        );
        assertEq(deployment.optimisticTokenVotingPluginRepo.latestRelease(), 1, "Invalid latestRelease");
        assertEq(deployment.optimisticTokenVotingPluginRepo.buildCount(1), 1, "Invalid buildCount");
        version = deployment.optimisticTokenVotingPluginRepo.getLatestVersion(1);
        assertEq(
            address(version.pluginSetup),
            address(optimisticTokenVotingPluginSetup),
            "Invalid optimisticTokenVotingPluginSetup"
        );

        // ENCRYPTION REGISTRY
        assertNotEq(address(deployment.encryptionRegistry), address(0), "Empty encryptionRegistry field");
        assertEq(
            deployment.encryptionRegistry.getRegisteredAccounts().length, 0, "Invalid getRegisteredAccounts().length"
        );
    }

    function test_StandardDeployment_2() public {
        DAO tempMgmtDao = DAO(
            payable(
                createProxyAndCall(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
        TaikoL1Mock taikoL1ContractAddress = new TaikoL1Mock();
        address taikoBridgeAddress = address(0x5678);
        address[] memory multisigMembers = new address[](16);
        for (uint256 i = 0; i < 16; i++) {
            multisigMembers[i] = address(uint160(i + 1));
        }

        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: new address[](0), amounts: new uint256[](0)});
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup = new OptimisticTokenVotingPluginSetup(
            new GovernanceERC20(tempMgmtDao, "", "", mintSettings), new GovernanceWrappedERC20(tokenAddress, "", "")
        );

        PluginRepoFactory pRefoFactory;
        MockPluginSetupProcessor psp;
        {
            MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
            pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));

            address[] memory setups = new address[](3);
            // adding in reverse order (stack)
            setups[2] = address(multisigPluginSetup);
            setups[1] = address(emergencyMultisigPluginSetup);
            setups[0] = address(optimisticTokenVotingPluginSetup);
            psp = new MockPluginSetupProcessor(setups);
        }
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            excludedVotingPowerHolders: getExcludedVotingPowerHolders(),
            timelockPeriod: 9 days, // uint32
            l2InactivityPeriod: 27 minutes, // uint32
            l2AggregationGracePeriod: 3 days, // uint32
            skipL2: true,
            // Voting settings
            minVetoRatio: 456_000, // uint32
            minStdProposalDuration: 21 days, // uint32
            minStdApprovals: 9, // uint16
            minEmergencyApprovals: 15, // uint16
            // OSx contracts
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)), // PluginSetupProcessor
            pluginRepoFactory: PluginRepoFactory(address(pRefoFactory)), // PluginRepoFactory
            // Plugin setup's
            multisigPluginSetup: multisigPluginSetup,
            emergencyMultisigPluginSetup: emergencyMultisigPluginSetup,
            optimisticTokenVotingPluginSetup: optimisticTokenVotingPluginSetup,
            // Multisig
            multisigMembers: multisigMembers, // address[]
            multisigExpirationPeriod: 22 days,
            // ENS
            stdMultisigEnsDomain: "multisig", // string
            emergencyMultisigEnsDomain: "eMultisig", // string
            optimisticTokenVotingEnsDomain: "optimistic" // string
        });

        // Deploy
        TaikoDaoFactory factory = new TaikoDaoFactory(creationSettings);

        factory.deployOnce();
        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();

        vm.roll(block.number + 1); // mint one block

        // DAO checks

        assertNotEq(address(deployment.dao), address(0), "Empty DAO field");
        assertEq(deployment.dao.daoURI(), "", "DAO URI should be empty");
        assertEq(address(deployment.dao.signatureValidator()), address(0), "signatureValidator should be empty");
        assertEq(address(deployment.dao.getTrustedForwarder()), address(0), "trustedForwarder should be empty");
        assertEq(
            deployment.dao.hasPermission(
                address(deployment.dao), address(deployment.dao), deployment.dao.ROOT_PERMISSION_ID(), bytes("")
            ),
            true,
            "The DAO should be ROOT on itself"
        );
        assertEq(
            deployment.dao.hasPermission(
                address(deployment.dao), address(deployment.dao), deployment.dao.UPGRADE_DAO_PERMISSION_ID(), bytes("")
            ),
            true,
            "The DAO should have UPGRADE_DAO_PERMISSION on itself"
        );
        assertEq(
            deployment.dao.hasPermission(
                address(deployment.dao),
                address(deployment.dao),
                deployment.dao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID(),
                bytes("")
            ),
            true,
            "The DAO should have REGISTER_STANDARD_CALLBACK_PERMISSION_ID on itself"
        );

        // Signer List

        assertEq(deployment.signerList.addresslistLength(), 16, "Invalid addresslistLength");
        for (uint256 i = 0; i < 16; i++) {
            assertEq(deployment.signerList.isListed(multisigMembers[i]), true, "Should be a member");
        }
        for (uint256 i = 17; i < 50; i++) {
            assertEq(deployment.signerList.isListed(address(uint160(i))), false, "Should not be a member");
        }

        // Multisig plugin

        assertNotEq(address(deployment.multisigPlugin), address(0), "Empty multisig field");
        assertEq(
            deployment.multisigPlugin.lastMultisigSettingsChange(),
            block.number - 1,
            "Invalid lastMultisigSettingsChange"
        );
        assertEq(deployment.multisigPlugin.proposalCount(), 0, "Invalid proposal count");

        {
            (
                bool onlyListed,
                uint16 minApprovals,
                uint64 destinationProposalDuration,
                SignerList signerList,
                uint64 expirationPeriod
            ) = deployment.multisigPlugin.multisigSettings();

            assertEq(onlyListed, true, "Invalid onlyListed");
            assertEq(minApprovals, 9, "Invalid minApprovals");
            assertEq(destinationProposalDuration, 21 days, "Invalid destinationProposalDuration");
            assertEq(address(signerList), address(deployment.signerList), "Incorrect signerList");
            assertEq(expirationPeriod, 22 days, "Invalid expirationPeriod");
        }

        // Emergency Multisig plugin

        assertNotEq(address(deployment.emergencyMultisigPlugin), address(0), "Empty emergencyMultisig field");
        assertEq(
            deployment.emergencyMultisigPlugin.lastMultisigSettingsChange(),
            block.number - 1,
            "Invalid lastMultisigSettingsChange"
        );
        assertEq(deployment.emergencyMultisigPlugin.proposalCount(), 0, "Invalid proposal count");
        {
            (bool onlyListed, uint16 minApprovals, Addresslist signerList, uint64 expirationPeriod) =
                deployment.emergencyMultisigPlugin.multisigSettings();

            assertEq(onlyListed, true, "Invalid onlyListed");
            assertEq(minApprovals, 15, "Invalid minApprovals");
            assertEq(address(signerList), address(deployment.signerList), "Invalid signerList");
            assertEq(expirationPeriod, 22 days, "Invalid expirationPeriod");
        }

        // Optimistic token voting plugin checks

        assertNotEq(
            address(deployment.optimisticTokenVotingPlugin), address(0), "Empty optimisticTokenVotingPlugin field"
        );
        assertEq(
            address(deployment.optimisticTokenVotingPlugin.votingToken()), address(tokenAddress), "Invalid votingToken"
        );
        assertEq(
            address(deployment.optimisticTokenVotingPlugin.taikoL1()),
            address(taikoL1ContractAddress),
            "Invalid taikoL1"
        );
        assertEq(
            address(deployment.optimisticTokenVotingPlugin.taikoBridge()),
            address(taikoBridgeAddress),
            "Invalid taikoBridge"
        );
        assertEq(deployment.optimisticTokenVotingPlugin.proposalCount(), 0, "Invalid proposal count");
        {
            (
                uint32 minVetoRatio,
                uint32 minDuration,
                uint32 timelockPeriod,
                uint32 l2InactivityPeriod,
                uint32 l2AggregationGracePeriod,
                bool skipL2
            ) = deployment.optimisticTokenVotingPlugin.governanceSettings();

            assertEq(minVetoRatio, 456_000, "Invalid minVetoRatio");
            assertEq(minDuration, 0, "Invalid minDuration"); // 10 days is enforced on the condition contract
            assertEq(timelockPeriod, 9 days, "Invalid timelockPeriod");
            assertEq(l2InactivityPeriod, 27 minutes, "Invalid l2InactivityPeriod");
            assertEq(l2AggregationGracePeriod, 3 days, "Invalid l2AggregationGracePeriod");
            assertEq(skipL2, true, "Invalid skipL2");
        }

        // PLUGIN REPO's

        PluginRepo.Version memory version;

        // Multisig repo
        assertNotEq(address(deployment.multisigPluginRepo), address(0), "Empty multisigPluginRepo field");
        assertEq(deployment.multisigPluginRepo.latestRelease(), 1, "Invalid latestRelease");
        assertEq(deployment.multisigPluginRepo.buildCount(1), 1, "Invalid buildCount");
        version = deployment.multisigPluginRepo.getLatestVersion(1);
        assertEq(address(version.pluginSetup), address(multisigPluginSetup), "Invalid multisigPluginSetup");

        // Emergency multisig repo
        assertNotEq(
            address(deployment.emergencyMultisigPluginRepo), address(0), "Empty emergencyMultisigPluginRepo field"
        );
        assertEq(deployment.emergencyMultisigPluginRepo.latestRelease(), 1, "Invalid latestRelease");
        assertEq(deployment.emergencyMultisigPluginRepo.buildCount(1), 1, "Invalid buildCount");
        version = deployment.emergencyMultisigPluginRepo.getLatestVersion(1);
        assertEq(
            address(version.pluginSetup), address(emergencyMultisigPluginSetup), "Invalid emergencyMultisigPluginSetup"
        );

        // Optimistic repo
        assertNotEq(
            address(deployment.optimisticTokenVotingPluginRepo),
            address(0),
            "Empty optimisticTokenVotingPluginRepo field"
        );
        assertEq(deployment.optimisticTokenVotingPluginRepo.latestRelease(), 1, "Invalid latestRelease");
        assertEq(deployment.optimisticTokenVotingPluginRepo.buildCount(1), 1, "Invalid buildCount");
        version = deployment.optimisticTokenVotingPluginRepo.getLatestVersion(1);
        assertEq(
            address(version.pluginSetup),
            address(optimisticTokenVotingPluginSetup),
            "Invalid optimisticTokenVotingPluginSetup"
        );

        // ENCRYPTION REGISTRY
        assertNotEq(address(deployment.encryptionRegistry), address(0), "Empty encryptionRegistry field");
        assertEq(
            deployment.encryptionRegistry.getRegisteredAccounts().length, 0, "Invalid getRegisteredAccounts().length"
        );
    }

    function test_TheDaoShouldOwnTheSignerList() public {
        DAO tempMgmtDao = DAO(
            payable(
                createProxyAndCall(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
        TaikoL1Mock taikoL1ContractAddress = new TaikoL1Mock();
        address taikoBridgeAddress = address(0x5678);
        address[] memory multisigMembers = new address[](16);
        for (uint256 i = 0; i < 16; i++) {
            multisigMembers[i] = address(uint160(i + 1));
        }

        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: new address[](0), amounts: new uint256[](0)});
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup = new OptimisticTokenVotingPluginSetup(
            new GovernanceERC20(tempMgmtDao, "", "", mintSettings), new GovernanceWrappedERC20(tokenAddress, "", "")
        );

        PluginRepoFactory pRefoFactory;
        MockPluginSetupProcessor psp;
        {
            MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
            pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));

            address[] memory setups = new address[](3);
            // adding in reverse order (stack)
            setups[2] = address(multisigPluginSetup);
            setups[1] = address(emergencyMultisigPluginSetup);
            setups[0] = address(optimisticTokenVotingPluginSetup);
            psp = new MockPluginSetupProcessor(setups);
        }
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            excludedVotingPowerHolders: getExcludedVotingPowerHolders(),
            timelockPeriod: 9 days, // uint32
            l2InactivityPeriod: 27 minutes, // uint32
            l2AggregationGracePeriod: 3 days, // uint32
            skipL2: true,
            // Voting settings
            minVetoRatio: 456_000, // uint32
            minStdProposalDuration: 21 days, // uint32
            minStdApprovals: 9, // uint16
            minEmergencyApprovals: 15, // uint16
            // OSx contracts
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)), // PluginSetupProcessor
            pluginRepoFactory: PluginRepoFactory(address(pRefoFactory)), // PluginRepoFactory
            // Plugin setup's
            multisigPluginSetup: multisigPluginSetup,
            emergencyMultisigPluginSetup: emergencyMultisigPluginSetup,
            optimisticTokenVotingPluginSetup: optimisticTokenVotingPluginSetup,
            // Multisig
            multisigMembers: multisigMembers, // address[]
            multisigExpirationPeriod: 22 days,
            // ENS
            stdMultisigEnsDomain: "multisig", // string
            emergencyMultisigEnsDomain: "eMultisig", // string
            optimisticTokenVotingEnsDomain: "optimistic" // string
        });

        // Deploy
        TaikoDaoFactory factory = new TaikoDaoFactory(creationSettings);

        factory.deployOnce();
        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();

        bool hasPerm = deployment.dao.hasPermission(
            address(deployment.signerList),
            address(deployment.dao),
            UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID,
            bytes("")
        );
        assertEq(hasPerm, true, "DAO should have UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID");
    }

    function test_AllContractsPointToTheDao() public {
        DAO tempMgmtDao = DAO(
            payable(
                createProxyAndCall(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
        TaikoL1Mock taikoL1ContractAddress = new TaikoL1Mock();
        address taikoBridgeAddress = address(0x5678);
        address[] memory multisigMembers = new address[](16);
        for (uint256 i = 0; i < 16; i++) {
            multisigMembers[i] = address(uint160(i + 1));
        }

        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: new address[](0), amounts: new uint256[](0)});
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup = new OptimisticTokenVotingPluginSetup(
            new GovernanceERC20(tempMgmtDao, "", "", mintSettings), new GovernanceWrappedERC20(tokenAddress, "", "")
        );

        PluginRepoFactory pRefoFactory;
        MockPluginSetupProcessor psp;
        {
            MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
            pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));

            address[] memory setups = new address[](3);
            // adding in reverse order (stack)
            setups[2] = address(multisigPluginSetup);
            setups[1] = address(emergencyMultisigPluginSetup);
            setups[0] = address(optimisticTokenVotingPluginSetup);
            psp = new MockPluginSetupProcessor(setups);
        }
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            excludedVotingPowerHolders: getExcludedVotingPowerHolders(),
            timelockPeriod: 9 days, // uint32
            l2InactivityPeriod: 27 minutes, // uint32
            l2AggregationGracePeriod: 3 days, // uint32
            skipL2: true,
            // Voting settings
            minVetoRatio: 456_000, // uint32
            minStdProposalDuration: 21 days, // uint32
            minStdApprovals: 9, // uint16
            minEmergencyApprovals: 15, // uint16
            // OSx contracts
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)), // PluginSetupProcessor
            pluginRepoFactory: PluginRepoFactory(address(pRefoFactory)), // PluginRepoFactory
            // Plugin setup's
            multisigPluginSetup: multisigPluginSetup,
            emergencyMultisigPluginSetup: emergencyMultisigPluginSetup,
            optimisticTokenVotingPluginSetup: optimisticTokenVotingPluginSetup,
            // Multisig
            multisigMembers: multisigMembers, // address[]
            multisigExpirationPeriod: 22 days,
            // ENS
            stdMultisigEnsDomain: "multisig", // string
            emergencyMultisigEnsDomain: "eMultisig", // string
            optimisticTokenVotingEnsDomain: "optimistic" // string
        });

        // Deploy
        TaikoDaoFactory factory = new TaikoDaoFactory(creationSettings);

        factory.deployOnce();
        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();

        // DAO linked
        assertEq(address(deployment.multisigPlugin.dao()), address(deployment.dao), "Incorrect DAO address");
        assertEq(address(deployment.emergencyMultisigPlugin.dao()), address(deployment.dao), "Incorrect DAO address");
        assertEq(
            address(deployment.optimisticTokenVotingPlugin.dao()), address(deployment.dao), "Incorrect DAO address"
        );
        assertEq(address(deployment.signerList.dao()), address(deployment.dao), "Incorrect DAO address");

        // DAO with permission
        bool hasPerm = deployment.dao.hasPermission(
            address(deployment.multisigPluginRepo),
            address(deployment.dao),
            deployment.multisigPluginRepo.MAINTAINER_PERMISSION_ID(),
            bytes("")
        );
        assertEq(hasPerm, true, "Incorrect hasPermission");

        hasPerm = deployment.dao.hasPermission(
            address(deployment.emergencyMultisigPluginRepo),
            address(deployment.dao),
            deployment.emergencyMultisigPluginRepo.MAINTAINER_PERMISSION_ID(),
            bytes("")
        );
        assertEq(hasPerm, true, "Incorrect hasPermission");

        hasPerm = deployment.dao.hasPermission(
            address(deployment.optimisticTokenVotingPluginRepo),
            address(deployment.dao),
            deployment.optimisticTokenVotingPluginRepo.MAINTAINER_PERMISSION_ID(),
            bytes("")
        );
        assertEq(hasPerm, true, "Incorrect hasPermission");
    }

    function test_MultipleDeploysDoNothing() public {
        DAO tempMgmtDao = DAO(
            payable(
                createProxyAndCall(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
        TaikoL1Mock taikoL1ContractAddress = new TaikoL1Mock();
        address taikoBridgeAddress = address(0x1234);
        address[] memory multisigMembers = new address[](13);
        for (uint256 i = 0; i < 13; i++) {
            multisigMembers[i] = address(uint160(i + 1));
        }

        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: new address[](0), amounts: new uint256[](0)});
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup = new OptimisticTokenVotingPluginSetup(
            new GovernanceERC20(tempMgmtDao, "", "", mintSettings), new GovernanceWrappedERC20(tokenAddress, "", "")
        );

        PluginRepoFactory pRefoFactory;
        MockPluginSetupProcessor psp;
        {
            MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
            pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));

            address[] memory setups = new address[](3);
            // adding in reverse order (stack)
            setups[2] = address(multisigPluginSetup);
            setups[1] = address(emergencyMultisigPluginSetup);
            setups[0] = address(optimisticTokenVotingPluginSetup);
            psp = new MockPluginSetupProcessor(setups);
        }
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            excludedVotingPowerHolders: getExcludedVotingPowerHolders(),
            timelockPeriod: 11 days,
            l2InactivityPeriod: 10 minutes, // uint32
            l2AggregationGracePeriod: 2 days, // uint32
            skipL2: false,
            // Voting settings
            minVetoRatio: 200_000, // uint32
            minStdProposalDuration: 10 days, // uint32
            minStdApprovals: 7, // uint16
            minEmergencyApprovals: 11, // uint16
            // OSx contracts
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)), // PluginSetupProcessor
            pluginRepoFactory: PluginRepoFactory(address(pRefoFactory)), // PluginRepoFactory
            // Plugin setup's
            multisigPluginSetup: multisigPluginSetup,
            emergencyMultisigPluginSetup: emergencyMultisigPluginSetup,
            optimisticTokenVotingPluginSetup: optimisticTokenVotingPluginSetup,
            // Multisig
            multisigMembers: multisigMembers, // address[]
            multisigExpirationPeriod: 10 days,
            // ENS
            stdMultisigEnsDomain: "multisig", // string
            emergencyMultisigEnsDomain: "eMultisig", // string
            optimisticTokenVotingEnsDomain: "optimistic" // string
        });

        TaikoDaoFactory factory = new TaikoDaoFactory(creationSettings);
        // ok
        factory.deployOnce();

        vm.expectRevert(abi.encodeWithSelector(TaikoDaoFactory.AlreadyDeployed.selector));
        factory.deployOnce();

        vm.expectRevert(abi.encodeWithSelector(TaikoDaoFactory.AlreadyDeployed.selector));
        factory.deployOnce();
    }
}
