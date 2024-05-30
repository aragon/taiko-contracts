// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "../base/AragonTest.sol";
import {TaikoDaoFactory} from "../../src/factory/TaikoDaoFactory.sol";
import {GovernanceERC20Mock} from "../mocks/GovernanceERC20Mock.sol";
import {TaikoL1Mock} from "../mocks/TaikoL1Mock.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {ENSRegistry} from "@ensdomains/ens-contracts/contracts/registry/ENSRegistry.sol";
import {PublicResolver} from "@ensdomains/ens-contracts/contracts/resolvers/PublicResolver.sol";
import {NameWrapper} from "@ensdomains/ens-contracts/contracts/wrapper/NameWrapper.sol";
import {createProxyAndCall} from "../../src/helpers/proxy.sol";

contract TaikoDaoFactoryTest is AragonTest {
    function test_ShouldStoreTheSettings() public {
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
        PluginRepoFactory pRefoFactory;
        PluginSetupProcessor psp;
        {
            ENSRegistry registry = new ENSRegistry();
            PublicResolver resolver = new PublicResolver(registry, new NameWrapper(), address(0), address(0));

            bytes32 node = bytes32(uint256(0x1234));
            ENSSubdomainRegistrar ensSubdomainReg = ENSSubdomainRegistrar(
                payable(
                    createProxyAndCall(
                        address(new ENSSubdomainRegistrar()),
                        abi.encodeCall(ENSSubdomainRegistrar.initialize, (tempMgmtDao, registry, node))
                    )
                )
            );
            PluginRepoRegistry pRepoRegistry = PluginRepoRegistry(
                payable(
                    createProxyAndCall(
                        address(new PluginRepoRegistry()),
                        abi.encodeCall(PluginRepoRegistry.initialize, (tempMgmtDao, ensSubdomainReg))
                    )
                )
            );
            pRefoFactory = new PluginRepoFactory(pRepoRegistry);
            psp = new PluginSetupProcessor(pRepoRegistry);
        }

        TaikoDaoFactory.DeploymentSettings memory creationSettings = TaikoDaoFactory.DeploymentSettings({
            // Taiko contract settings
            tokenAddress: tokenAddress,
            taikoL1ContractAddress: address(taikoL1ContractAddress), // address
            taikoBridgeAddress: taikoBridgeAddress, // address
            l2InactivityPeriod: 10 minutes, // uint64
            l2AggregationGracePeriod: 2 days, // uint64
            // Voting settings
            minVetoRatio: 200_000, // uint32
            minStdProposalDelay: 10 days, // uint64
            minStdApprovals: 7, // uint16
            minEmergencyApprovals: 11, // uint16
            // OSx contracts
            pluginSetupProcessor: psp, // PluginSetupProcessor
            pluginRepoFactory: pRefoFactory, // PluginRepoFactory
            // Token contracts
            governanceErc20Base: new GovernanceERC20(
                tempMgmtDao, "", "", GovernanceERC20.MintSettings(new address[](0), new uint256[](0))
            ), // GovernanceERC20
            governanceErcWrapped20Base: new GovernanceWrappedERC20(tokenAddress, "", ""), // GovernanceWrappedERC20
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
        assertEq(actualSettings.minVetoRatio, creationSettings.minVetoRatio, "Incorrect minVetoRatio");
        assertEq(
            actualSettings.minStdProposalDelay, creationSettings.minStdProposalDelay, "Incorrect minStdProposalDelay"
        );
        assertEq(actualSettings.minStdApprovals, creationSettings.minStdApprovals, "Incorrect minStdApprovals");
        assertEq(
            actualSettings.minEmergencyApprovals,
            creationSettings.minEmergencyApprovals,
            "Incorrect minEmergencyApprovals"
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
            address(actualSettings.governanceErc20Base),
            address(creationSettings.governanceErc20Base),
            "Incorrect governanceErc20Base"
        );
        assertEq(
            address(actualSettings.governanceErcWrapped20Base),
            address(creationSettings.governanceErcWrapped20Base),
            "Incorrect governanceErcWrapped20Base"
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

    // function test_StandardDeployment() public {
    //     DAO tempMgmtDao = new DAO();
    //     tempMgmtDao.initialize("", address(this), address(0), "");

    //     GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
    //     TaikoL1Mock taikoL1ContractAddress = new TaikoL1Mock();
    //     address taikoBridgeAddress = address(0x1234);
    //     address[] memory multisigMembers = new address[](13);
    //     PluginRepoFactory pRefoFactory;
    //     PluginSetupProcessor psp;
    //     {
    //         PluginRepoRegistry pRepoRegistry = new PluginRepoRegistry();
    //         ENSSubdomainRegistrar ensSubdomainReg = new ENSSubdomainRegistrar();
    //         ENSRegistry registry = new ENSRegistry();
    //         ensSubdomainReg.initialize(tempMgmtDao, registry, bytes32(uint256(0x1234)));
    //         pRepoRegistry.initialize(tempMgmtDao, ensSubdomainReg);
    //         pRefoFactory = new PluginRepoFactory(pRepoRegistry);
    //         psp = new PluginSetupProcessor(pRepoRegistry);
    //     }

    //     TaikoDaoFactory.DeploymentSettings memory settings = TaikoDaoFactory.DeploymentSettings({
    //         // Taiko contract settings
    //         tokenAddress: tokenAddress,
    //         taikoL1ContractAddress: address(taikoL1ContractAddress), // address
    //         taikoBridgeAddress: taikoBridgeAddress, // address
    //         l2InactivityPeriod: 10 minutes, // uint64
    //         l2AggregationGracePeriod: 2 days, // uint64
    //         // Voting settings
    //         minVetoRatio: 200_000, // uint32
    //         minStdProposalDelay: 10 days, // uint64
    //         minStdApprovals: 7, // uint16
    //         minEmergencyApprovals: 11, // uint16
    //         // OSx contracts
    //         pluginSetupProcessor: psp, // PluginSetupProcessor
    //         pluginRepoFactory: pRefoFactory, // PluginRepoFactory
    //         // Token contracts
    //         governanceErc20Base: new GovernanceERC20(
    //             tempMgmtDao, "", "", GovernanceERC20.MintSettings(new address[](0), new uint256[](0))
    //         ), // GovernanceERC20
    //         governanceErcWrapped20Base: new GovernanceWrappedERC20(tokenAddress, "", ""), // GovernanceWrappedERC20
    //         // Multisig
    //         multisigMembers: multisigMembers, // address[]
    //         // ENS
    //         stdMultisigEnsDomain: "multisig", // string
    //         emergencyMultisigEnsDomain: "eMultisig", // string
    //         optimisticTokenVotingEnsDomain: "optimistic" // string
    //     });

    //     TaikoDaoFactory factory = new TaikoDaoFactory(settings);
    //     factory.getDeployment();
    // }
}
