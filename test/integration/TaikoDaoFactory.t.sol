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
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {createProxyAndCall} from "../../src/helpers/proxy.sol";
import {MultisigPluginSetup} from "../../src/setup/MultisigPluginSetup.sol";
import {EmergencyMultisigPluginSetup} from "../../src/setup/EmergencyMultisigPluginSetup.sol";
import {OptimisticTokenVotingPluginSetup} from "../../src/setup/OptimisticTokenVotingPluginSetup.sol";

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
            new OptimisticTokenVotingPluginSetup(GovernanceERC20(address(0)), GovernanceWrappedERC20(address(0)));

        MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
        PluginRepoFactory pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));
        MockPluginSetupProcessor psp = new MockPluginSetupProcessor(new address[](0));
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            l2InactivityPeriod: 10 minutes, // uint64
            l2AggregationGracePeriod: 2 days, // uint64
            skipL2: false,
            // Voting settings
            minVetoRatio: 200_000, // uint32
            minStdProposalDuration: 10 days, // uint64
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
        address[] memory multisigMembers = new address[](20);

        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup =
            new OptimisticTokenVotingPluginSetup(GovernanceERC20(address(0)), GovernanceWrappedERC20(address(0)));

        MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
        PluginRepoFactory pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));
        MockPluginSetupProcessor psp = new MockPluginSetupProcessor(new address[](0));
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            l2InactivityPeriod: 27 minutes, // uint64
            l2AggregationGracePeriod: 77 days, // uint64
            skipL2: false,
            // Voting settings
            minVetoRatio: 456_000, // uint32
            minStdProposalDuration: 14 days, // uint64
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

    function test_StandardDeployment() public {
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

        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup =
            new OptimisticTokenVotingPluginSetup(GovernanceERC20(address(0)), GovernanceWrappedERC20(address(0)));

        PluginRepoFactory pRefoFactory;
        MockPluginSetupProcessor psp;
        {
            MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
            pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));

            address[] memory setups = new address[](3);
            setups[0] = address(multisigPluginSetup);
            setups[1] = address(emergencyMultisigPluginSetup);
            setups[2] = address(optimisticTokenVotingPluginSetup);
            psp = new MockPluginSetupProcessor(setups);
        }
        MockDaoFactory daoFactory = new MockDaoFactory(psp);

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            l2InactivityPeriod: 10 minutes, // uint64
            l2AggregationGracePeriod: 2 days, // uint64
            skipL2: false,
            // Voting settings
            minVetoRatio: 200_000, // uint32
            minStdProposalDuration: 10 days, // uint64
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
            // ENS
            stdMultisigEnsDomain: "multisig", // string
            emergencyMultisigEnsDomain: "eMultisig", // string
            optimisticTokenVotingEnsDomain: "optimistic" // string
        });

        TaikoDaoFactory factory = new TaikoDaoFactory(creationSettings);
        factory.deployOnce();

        TaikoDaoFactory.Deployment memory deployment = factory.getDeployment();

        // TODO:
    }
}
