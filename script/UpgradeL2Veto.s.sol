// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {ScriptBase} from "./lib/ScriptBase.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {IPermissionCondition} from "@aragon/osx/core/permission/IPermissionCondition.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {
    UpgradeOptimisticTokenVotingPluginFactory
} from "../src/factory/UpgradeOptimisticTokenVotingPluginFactory.sol";
import {L2VetoReceiver} from "../src/crosschain/L2VetoReceiver.sol";
import {L2VetoAggregator} from "../src/crosschain/L2VetoAggregator.sol";

/// @title UpgradeL2Veto
/// @notice Single multi-chain script that deploys all L2 veto contracts (L1 + L2)
///         and generates a single DAO proposal to upgrade and configure everything.
/// @dev Deployment flow:
///      1. Run this script — deploys on both chains, outputs one proposal JSON
///      2. Submit the single DAO proposal
///
///      Uses vm.createSelectFork() to switch between L1 and L2 chains.
///      Requires L1_CHAIN and L2_CHAIN env vars matching foundry.toml [rpc_endpoints] keys.
contract UpgradeL2Veto is ScriptBase {
    function run() external {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        string memory l1Chain = vm.envString("L1_CHAIN");
        string memory l2Chain = vm.envString("L2_CHAIN");

        // Deploy on L1
        vm.createSelectFork(l1Chain);
        (L2VetoReceiver receiver, UpgradeOptimisticTokenVotingPluginFactory factory) = _deployL1(privKey);

        // Deploy on L2
        vm.createSelectFork(l2Chain);
        L2VetoAggregator aggregator = _deployL2(privKey, address(receiver));

        // Build proposal and write files (switch back to L1 for on-chain reads)
        vm.createSelectFork(l1Chain);
        _buildAndWriteProposal(receiver, factory, aggregator);
        _writeDeployments(l1Chain, l2Chain, receiver, factory, aggregator);

        console.log("");
        console.log("Next step: submit proposals/proposal-upgrade-l2-veto.json to the DAO");
    }

    function _deployL1(uint256 _privKey)
        internal
        returns (L2VetoReceiver receiver, UpgradeOptimisticTokenVotingPluginFactory factory)
    {
        address dao = vm.envAddress("DAO_ADDRESS");
        address plugin = vm.envAddress("PLUGIN_ADDRESS");
        address l1TaikoBridge = vm.envAddress("L1_TAIKO_BRIDGE");
        uint64 l2ChainId = uint64(vm.envUint("L2_CHAIN_ID"));

        vm.startBroadcast(_privKey);

        receiver = new L2VetoReceiver(IDAO(dao), l1TaikoBridge, l2ChainId, plugin);
        console.log("L2VetoReceiver (L1):", address(receiver));

        factory = new UpgradeOptimisticTokenVotingPluginFactory(
            GovernanceERC20(vm.envAddress("GOVERNANCE_ERC20_BASE")),
            GovernanceWrappedERC20(vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE"))
        );
        console.log("UpgradeFactory (L1):", address(factory));
        console.log("  New PluginSetup:", address(factory.newSetup()));
        console.log("  New implementation:", factory.newSetup().implementation());

        vm.stopBroadcast();
    }

    function _deployL2(uint256 _privKey, address _receiver) internal returns (L2VetoAggregator aggregator) {
        address l2TaikoBridge = vm.envAddress("L2_TAIKO_BRIDGE");
        uint64 l1ChainId = uint64(vm.envUint("L1_CHAIN_ID"));
        address l2VotingToken = vm.envAddress("L2_VOTING_TOKEN");

        vm.startBroadcast(_privKey);

        aggregator = new L2VetoAggregator(l2TaikoBridge, l1ChainId, l2VotingToken, _receiver);
        console.log("L2VetoAggregator (L2):", address(aggregator));

        vm.stopBroadcast();
    }

    function _buildAndWriteProposal(
        L2VetoReceiver _receiver,
        UpgradeOptimisticTokenVotingPluginFactory _factory,
        L2VetoAggregator _aggregator
    ) internal {
        address dao = vm.envAddress("DAO_ADDRESS");
        address pluginRepo = vm.envAddress("PLUGIN_REPO_ADDRESS");

        UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams memory params =
            UpgradeOptimisticTokenVotingPluginFactory.UpgradeParams({
                dao: DAO(payable(dao)),
                psp: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS")),
                plugin: OptimisticTokenVotingPlugin(vm.envAddress("PLUGIN_ADDRESS")),
                pluginRepo: PluginRepo(pluginRepo),
                votingToken: vm.envAddress("L1_VOTING_TOKEN"),
                l2VetoReceiver: address(_receiver)
            });

        bytes32 rootPermission = DAO(payable(dao)).ROOT_PERMISSION_ID();
        bytes32 maintainerPermission = PluginRepo(pluginRepo).MAINTAINER_PERMISSION_ID();
        bytes32 proposerPermission = keccak256("PROPOSER_PERMISSION");

        address stdProposer = vm.envAddress("MULTISIG_PLUGIN_ADDRESS");
        address stdProposalCondition = vm.envAddress("STANDARD_PROPOSAL_CONDITION");
        address plugin = vm.envAddress("PLUGIN_ADDRESS");

        IDAO.Action[] memory actions = new IDAO.Action[](7);
        actions[0] = IDAO.Action({
            to: dao,
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (dao, address(_factory), rootPermission))
        });
        actions[1] = IDAO.Action({
            to: pluginRepo,
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (pluginRepo, address(_factory), maintainerPermission))
        });
        actions[2] = IDAO.Action({
            to: address(_factory),
            value: 0,
            data: abi.encodeCall(UpgradeOptimisticTokenVotingPluginFactory.upgrade, (params))
        });
        actions[3] = IDAO.Action({
            to: pluginRepo,
            value: 0,
            data: abi.encodeCall(PermissionManager.revoke, (pluginRepo, address(_factory), maintainerPermission))
        });
        actions[4] = IDAO.Action({
            to: address(_receiver),
            value: 0,
            data: abi.encodeCall(L2VetoReceiver.setTrustedL2Aggregator, (address(_aggregator)))
        });
        // Fix: revoke unconditional PROPOSER_PERMISSION and re-grant with condition
        actions[5] = IDAO.Action({
            to: dao,
            value: 0,
            data: abi.encodeCall(PermissionManager.revoke, (plugin, stdProposer, proposerPermission))
        });
        actions[6] = IDAO.Action({
            to: dao,
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grantWithCondition,
                (plugin, stdProposer, proposerPermission, IPermissionCondition(stdProposalCondition))
            )
        });

        _writeProposal("proposal-upgrade-l2-veto.json", actions);
        _logActions(actions);
    }

    function _writeDeployments(
        string memory _l1Chain,
        string memory _l2Chain,
        L2VetoReceiver _receiver,
        UpgradeOptimisticTokenVotingPluginFactory _factory,
        L2VetoAggregator _aggregator
    ) private {
        string memory l1Key = "l1";
        vm.serializeString(l1Key, "chain", _l1Chain);
        vm.serializeAddress(l1Key, "l2VetoReceiver", address(_receiver));
        vm.serializeAddress(l1Key, "upgradeFactory", address(_factory));
        vm.serializeAddress(l1Key, "newPluginSetup", address(_factory.newSetup()));
        string memory l1Json =
            vm.serializeAddress(l1Key, "newImplementation", _factory.newSetup().implementation());

        string memory l2Key = "l2";
        vm.serializeString(l2Key, "chain", _l2Chain);
        string memory l2Json = vm.serializeAddress(l2Key, "l2VetoAggregator", address(_aggregator));

        string memory root = "deployments";
        vm.serializeString(root, "l1", l1Json);
        string memory finalJson = vm.serializeString(root, "l2", l2Json);

        string memory dir = string.concat(vm.projectRoot(), "/proposals");
        vm.createDir(dir, true);
        vm.writeFile(string.concat(dir, "/deployments.json"), finalJson);
        console.log("Wrote proposals/deployments.json");
    }

}
