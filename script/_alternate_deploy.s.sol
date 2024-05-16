// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {OptimisticTokenVotingPluginSetup} from "../src/setup/OptimisticTokenVotingPluginSetup.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

contract Deploy is Script {
    address governanceERC20Base;
    address governanceWrappedERC20Base;
    address pluginRepoFactory;
    DAOFactory daoFactory;
    address tokenAddress;
    string ensSubdomain;
    address[] pluginAddress;

    function setUp() public {
        governanceERC20Base = vm.envAddress("GOVERNANCE_ERC20_BASE");
        governanceWrappedERC20Base = vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE");
        pluginRepoFactory = vm.envAddress("PLUGIN_REPO_FACTORY");
        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY"));
        tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        ensSubdomain = string.concat("optimistic-crosschain-", vm.toString(block.timestamp));
    }

    function run() public {
        // 0. Setting up Foundry
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // 1. Deploying the Plugin Setup
        OptimisticTokenVotingPluginSetup pluginSetup = deployPluginSetup();

        // 2. Publishing it in the Aragon OSx Protocol
        PluginRepo pluginRepo = deployPluginRepo(address(pluginSetup));

        // 3. Defining the DAO Settings
        DAOFactory.DAOSettings memory daoSettings = getDAOSettings();

        // 4. Defining the plugin settings
        DAOFactory.PluginSettings[] memory pluginSettings = getPluginSettings(pluginRepo);

        // 5. Deploying the DAO
        vm.recordLogs();
        address createdDAO = address(daoFactory.createDao(daoSettings, pluginSettings));

        // 6. Getting the Plugin Address
        Vm.Log[] memory logEntries = vm.getRecordedLogs();

        for (uint256 i = 0; i < logEntries.length; i++) {
            if (logEntries[i].topics[0] == keccak256("InstallationApplied(address,address,bytes32,bytes32)")) {
                pluginAddress.push(address(uint160(uint256(logEntries[i].topics[2]))));
            }
        }

        vm.stopBroadcast();

        console2.log("Plugin Setup: ", address(pluginSetup));
        console2.log("Plugin Repo: ", address(pluginRepo));
        console2.log("Created DAO: ", address(createdDAO));
        console2.log("Installed Plugins: ");
        for (uint256 i = 0; i < pluginAddress.length; i++) {
            console2.log("- ", pluginAddress[i]);
        }
    }

    function deployPluginSetup() public returns (OptimisticTokenVotingPluginSetup) {
        OptimisticTokenVotingPluginSetup pluginSetup = new OptimisticTokenVotingPluginSetup(
            GovernanceERC20(governanceERC20Base), GovernanceWrappedERC20(governanceWrappedERC20Base)
        );
        return pluginSetup;
    }

    function deployPluginRepo(address pluginSetup) public returns (PluginRepo pluginRepo) {
        pluginRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepoWithFirstVersion(
            ensSubdomain,
            pluginSetup,
            msg.sender,
            "0x00", // TODO: Give these actual values on prod
            "0x00"
        );
    }

    function getDAOSettings() public view returns (DAOFactory.DAOSettings memory) {
        return DAOFactory.DAOSettings(address(0), "", ensSubdomain, "");
    }

    function getPluginSettings(PluginRepo pluginRepo)
        public
        view
        returns (DAOFactory.PluginSettings[] memory pluginSettings)
    {
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory votingSettings =
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings(200_000, 10 days, 10 minutes, 2 days);
        OptimisticTokenVotingPluginSetup.TokenSettings memory tokenSettings =
            OptimisticTokenVotingPluginSetup.TokenSettings(tokenAddress, "", "");

        address[] memory holders = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings(holders, amounts);

        address[] memory proposers = new address[](3);
        proposers[0] = 0x8bF1e340055c7dE62F11229A149d3A1918de3d74;
        proposers[1] = 0x35911Cc89aaBe7Af6726046823D5b678B6A1498d;
        proposers[2] = 0xa722c2c1f2218929945737EbdB8cB0f228E43265;

        bytes memory pluginSettingsData = abi.encode(votingSettings, tokenSettings, mintSettings, proposers);

        PluginRepo.Tag memory tag = PluginRepo.Tag(1, 1);
        pluginSettings = new DAOFactory.PluginSettings[](1);
        pluginSettings[0] = DAOFactory.PluginSettings(PluginSetupRef(tag, pluginRepo), pluginSettingsData);
    }
}
