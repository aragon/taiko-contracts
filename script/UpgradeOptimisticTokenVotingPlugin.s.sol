// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {
    UpgradeOptimisticTokenVotingPluginFactory
} from "../src/factory/UpgradeOptimisticTokenVotingPluginFactory.sol";
import {L2VetoReceiver} from "../src/crosschain/L2VetoReceiver.sol";

/// @title UpgradeOptimisticTokenVotingPlugin
/// @notice Deploys L2VetoReceiver + UpgradeFactory and writes the upgrade DAO proposal actions as JSON.
/// @dev Deployment flow:
///      1. Run this script on L1 — deploys L2VetoReceiver + UpgradeFactory
///      2. Submit DAO Proposal 1 (proposals/proposal-1-upgrade.json)
///      3. Deploy L2VetoAggregator on L2 (DeployL2VetoAggregator.s.sol)
///      4. Run FinalizeUpgrade.s.sol, submit Proposal 2 (proposals/proposal-2-finalize.json)
contract UpgradeOptimisticTokenVotingPlugin is Script {
    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        _;

        vm.stopBroadcast();
    }

    function run() external broadcast {
        address dao = vm.envAddress("DAO_ADDRESS");
        address plugin = vm.envAddress("PLUGIN_ADDRESS");
        address pluginRepo = vm.envAddress("PLUGIN_REPO_ADDRESS");
        address psp = vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS");
        address governanceERC20Base = vm.envAddress("GOVERNANCE_ERC20_BASE");
        address governanceWrappedERC20Base = vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE");
        address votingToken = vm.envAddress("L1_VOTING_TOKEN");
        address taikoBridge = vm.envAddress("L1_TAIKO_BRIDGE");
        uint64 l2ChainId = uint64(vm.envUint("L2_CHAIN_ID"));

        // Deploy L2VetoReceiver (L1)
        L2VetoReceiver l2VetoReceiver = new L2VetoReceiver(IDAO(dao), taikoBridge, l2ChainId, plugin);
        console.log("L2VetoReceiver:", address(l2VetoReceiver));

        // Deploy factory (which deploys the new PluginSetup internally)
        UpgradeOptimisticTokenVotingPluginFactory factory = new UpgradeOptimisticTokenVotingPluginFactory(
            GovernanceERC20(governanceERC20Base), GovernanceWrappedERC20(governanceWrappedERC20Base)
        );

        console.log("UpgradeFactory:", address(factory));
        console.log("New PluginSetup:", address(factory.newSetup()));
        console.log("New implementation:", factory.newSetup().implementation());

        // Build upgrade params
        UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams memory params =
            UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams({
                dao: DAO(payable(dao)),
                psp: PluginSetupProcessor(psp),
                plugin: OptimisticTokenVotingPlugin(plugin),
                pluginRepo: PluginRepo(pluginRepo),
                votingToken: votingToken,
                l2VetoReceiver: address(l2VetoReceiver)
            });

        _writeProposal1(dao, pluginRepo, factory, params);
        _writeDeployments(address(l2VetoReceiver), address(factory), factory);

        console.log("");
        console.log("Next steps:");
        console.log("  1. Submit proposals/proposal-1-upgrade.json");
        console.log("  2. Deploy L2VetoAggregator on L2 (DeployL2VetoAggregator.s.sol)");
        console.log("     Set L2_VETO_RECEIVER_ADDRESS=", address(l2VetoReceiver));
        console.log("  3. Run FinalizeUpgrade.s.sol to generate proposal-2-finalize.json");
        console.log("     Set FACTORY_ADDRESS=", address(factory));
        console.log("     Set L2_VETO_RECEIVER_ADDRESS=", address(l2VetoReceiver));
    }

    function _writeDeployments(
        address _l2VetoReceiver,
        address _factory,
        UpgradeOptimisticTokenVotingPluginFactory _factoryInstance
    ) internal {
        string memory key = "l1-deployments";
        vm.serializeAddress(key, "l2VetoReceiver", _l2VetoReceiver);
        vm.serializeAddress(key, "upgradeFactory", _factory);
        vm.serializeAddress(key, "newPluginSetup", address(_factoryInstance.newSetup()));
        string memory json = vm.serializeAddress(key, "newImplementation", _factoryInstance.newSetup().implementation());

        string memory dir = string.concat(vm.projectRoot(), "/proposals");
        vm.createDir(dir, true);
        vm.writeFile(string.concat(dir, "/l1-deployments.json"), json);
        console.log("Wrote proposals/l1-deployments.json");
    }

    function _writeProposal1(
        address _dao,
        address _pluginRepo,
        UpgradeOptimisticTokenVotingPluginFactory _factory,
        UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams memory _params
    ) internal {
        bytes32 rootPermission = DAO(payable(_dao)).ROOT_PERMISSION_ID();
        bytes32 maintainerPermission = PluginRepo(_pluginRepo).MAINTAINER_PERMISSION_ID();

        IDAO.Action[] memory actions = new IDAO.Action[](4);
        actions[0] = IDAO.Action({
            to: _dao,
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (_dao, address(_factory), rootPermission))
        });
        actions[1] = IDAO.Action({
            to: _pluginRepo,
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (_pluginRepo, address(_factory), maintainerPermission))
        });
        actions[2] = IDAO.Action({
            to: address(_factory),
            value: 0,
            data: abi.encodeCall(UpgradeOptimisticTokenVotingPluginFactory.upgrade, (_params))
        });
        actions[3] = IDAO.Action({
            to: _pluginRepo,
            value: 0,
            data: abi.encodeCall(PermissionManager.revoke, (_pluginRepo, address(_factory), maintainerPermission))
        });

        string memory dir = string.concat(vm.projectRoot(), "/proposals");
        vm.createDir(dir, true);
        string memory path = string.concat(dir, "/proposal-1-upgrade.json");
        vm.writeFile(path, _serializeActions(actions));
        console.log("Wrote proposals/proposal-1-upgrade.json");
    }

    function _serializeActions(IDAO.Action[] memory _actions) internal pure returns (string memory) {
        string memory json = "[\n";
        for (uint256 i = 0; i < _actions.length; i++) {
            json = string.concat(
                json,
                '  {"to":"',
                vm.toString(_actions[i].to),
                '","value":',
                vm.toString(_actions[i].value),
                ',"data":"',
                vm.toString(_actions[i].data),
                '"}'
            );
            if (i < _actions.length - 1) {
                json = string.concat(json, ",\n");
            }
        }
        return string.concat(json, "\n]");
    }
}
