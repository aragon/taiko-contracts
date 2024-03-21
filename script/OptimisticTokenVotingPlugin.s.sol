// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {OptimisticTokenVotingPluginSetup} from "../src/OptimisticTokenVotingPluginSetup.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {MultisigSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {Multisig} from "@aragon/osx/plugins/governance/multisig/Multisig.sol";
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

        // 0. Deployer wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Multisig plugin setup
        MultisigSetup multisigPluginSetup = new MultisigSetup();

        // 2. Publish the multisig plugin setup (repo)
        PluginRepo pluginRepo = PluginRepoFactory(pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                "ens-of-the-miultisig",
                address(multisigPluginSetup),
                msg.sender,
                "0x",
                "0x"
            );

        // 3. Optimistic token voting plugin setup
        OptimisticTokenVotingPluginSetup optPluginSetup = new OptimisticTokenVotingPluginSetup(
                GovernanceERC20(governanceERC20Base),
                GovernanceWrappedERC20(governanceWrappedERC20Base)
            );

        // 4. Publish the optimistic token voting plugin setup (repo)
        PluginRepo optPluginRepo = PluginRepoFactory(pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                "ens-of-the-optimistic-token-voting",
                address(optPluginSetup),
                msg.sender,
                "0x",
                "0x"
            );

        // 5. DAO Settings
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings(
            address(0),
            "",
            "ens-of-the-dao", // This should be changed on each deployment
            ""
        );

        // 6. Emergency multisig settings
        // TODO:

        // 7. Standard multisig settings
        // TODO:

        // 8. Optimistic token voting settings
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

        bytes memory pluginSettingsData = abi.encode(
            votingSettings,
            tokenSettings,
            mintSettings
        );

        PluginRepo.Tag memory tag = PluginRepo.Tag(1, 1);
        DAOFactory.PluginSettings[]
            memory pluginSettings = new DAOFactory.PluginSettings[](1);
        pluginSettings[0] = DAOFactory.PluginSettings(
            PluginSetupRef(tag, PluginRepo(pluginRepo)),
            pluginSettingsData
        );

        // 9. Deploying the DAO
        daoFactory.createDao(daoSettings, pluginSettings);

        vm.stopBroadcast();
    }
}
