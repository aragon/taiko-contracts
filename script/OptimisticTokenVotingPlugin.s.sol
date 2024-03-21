// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {OptimisticTokenVotingPluginSetup} from "../src/OptimisticTokenVotingPluginSetup.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

contract OptimisticTokenVotingPluginScript is Script {
    address governanceERC20Base;
    address governanceWrappedERC20Base;
    address pluginRepoFactory;
    DAOFactory daoFactory;
    uint16 l2ChainId;
    address lzEndpoint;
    address tokenAddress;
    address l2VotingAggregator;

    function setUp() public {
        governanceERC20Base = vm.envAddress("GOVERNANCE_ERC20_BASE");
        governanceWrappedERC20Base = vm.envAddress(
            "GOVERNANCE_WRAPPED_ERC20_BASE"
        );
        pluginRepoFactory = vm.envAddress("PLUGIN_REPO_FACTORY");
        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY"));
        l2ChainId = uint16(vm.envUint("L2_CHAIN_ID"));
        lzEndpoint = vm.envAddress("LZ_L1_ENDPOINT");
        tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        l2VotingAggregator = vm.envAddress("L2_VOTING_AGG");
    }

    function run() public {
        // 0. Setting up Foundry
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // 1. Deploying the Plugin Setup
        OptimisticTokenVotingPluginSetup pluginSetup = new OptimisticTokenVotingPluginSetup(
                GovernanceERC20(governanceERC20Base),
                GovernanceWrappedERC20(governanceWrappedERC20Base)
            );

        // 2. // 2. Publishing it in the Aragon OSx Protocol
        PluginRepo pluginRepo = PluginRepoFactory(pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                "optimisticCrosschain1",
                address(pluginSetup),
                msg.sender,
                "0x00", // TODO: Give these actual values on prod
                "0x00"
            );

        // 3. Defining the DAO Settings
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings(
            address(0),
            "",
            "optimisticCrosschain1", // This should be changed on each deployment
            ""
        );

        // 4. Defining the plugin settings
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory votingSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings(200000, 60 * 60 * 24 * 4, 0);
        OptimisticTokenVotingPluginSetup.TokenSettings
            memory tokenSettings = OptimisticTokenVotingPluginSetup
                .TokenSettings(tokenAddress, "", "");

        address[] memory holders = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20
            .MintSettings(holders, amounts);

        address[] memory proposers = new address[](1);
        proposers[0] = 0x8bF1e340055c7dE62F11229A149d3A1918de3d74;

        OptimisticTokenVotingPlugin.BridgeSettings
            memory bridgeSettings = OptimisticTokenVotingPlugin.BridgeSettings(
                l2ChainId,
                lzEndpoint,
                l2VotingAggregator
            );

        bytes memory pluginSettingsData = abi.encode(
            votingSettings,
            tokenSettings,
            mintSettings,
            proposers,
            bridgeSettings
        );

        PluginRepo.Tag memory tag = PluginRepo.Tag(1, 1);
        DAOFactory.PluginSettings[]
            memory pluginSettings = new DAOFactory.PluginSettings[](1);
        pluginSettings[0] = DAOFactory.PluginSettings(
            PluginSetupRef(tag, PluginRepo(pluginRepo)),
            pluginSettingsData
        );

        // 5. Deploying the DAO
        daoFactory.createDao(daoSettings, pluginSettings);

        vm.stopBroadcast();
    }
}
