// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {OptimisticTokenVotingPluginSetup} from "../src/OptimisticTokenVotingPluginSetup.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";

contract Deploy is Script {
    function run() public {
        address governanceERC20Base = vm.envAddress("GOVERNANCE_ERC20_BASE");
        address governanceWrappedERC20Base = vm.envAddress(
            "GOVERNANCE_WRAPPED_ERC20_BASE"
        );
        address pluginRepoFactory = vm.envAddress("PLUGIN_REPO_FACTORY");
        DAOFactory daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY"));
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");

        // 0. Setting up foundry
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        vm.createSelectFork(vm.rpcUrl("sepholia"));

        // 1. Deploying the Plugin Setup
        OptimisticTokenVotingPluginSetup pluginSetup = new OptimisticTokenVotingPluginSetup(
            GovernanceERC20(governanceERC20Base),
            GovernanceWrappedERC20(governanceWrappedERC20Base)
        );

        // 2. Publishing it in the Aragon OSx Protocol
        PluginRepo pluginRepo = PluginRepoFactory(pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                "tempan-plugin-v1",
                address(pluginSetup),
                msg.sender,
                "0x00", // TODO: Give these actual values on prod
                "0x00"
            );

        // 3. Defining the DAO Settings
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings(
            address(0),
            "",
            "tempan-dao-v1", // This should be changed on each deployment
            ""
        );

        // 4. Defining the plugin settings
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory votingSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings(200000, 60 * 60 * 24 * 4, 0);
        OptimisticTokenVotingPluginSetup.TokenSettings
            memory tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings(
                tokenAddress,
                "Tempan DAO Token",
                "TPT"
            );

        address[] memory holders = new address[](1);
        holders[0] = msg.sender;

        uint256[] memory amounts = new uint256[](0);
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20
            .MintSettings(holders, amounts);

        address _lzAppEndpoint = address(pluginSetup);

        bytes memory pluginSettingsData = abi.encode(
            votingSettings,
            tokenSettings,
            mintSettings,
            holders, // TODO: Is this correct?
            _lzAppEndpoint
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