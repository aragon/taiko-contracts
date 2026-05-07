// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {ScriptBase} from "../lib/ScriptBase.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {L2VetoReceiver} from "../../src/crosschain/L2VetoReceiver.sol";

/// @title EncodeProposal (Fresh deploy)
/// @notice Generates a DAO proposal JSON to wire L2VetoReceiver + L2VetoAggregator into the plugin.
/// @dev Step 3 of 3. Run against L1 RPC (reads on-chain permission constants).
///      Requires VETO_RECEIVER_ADDRESS and VETO_AGGREGATOR_ADDRESS from steps 1-2.
///      No broadcast — only encodes calldata and writes JSON.
contract EncodeProposal is ScriptBase {
    struct Config {
        address dao;
        address plugin;
        address vetoReceiver;
        address vetoAggregator;
    }

    function run() external {
        Config memory config = _loadConfig();

        bytes32 setAggregatorPermission =
            L2VetoReceiver(config.vetoReceiver).SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID();

        IDAO.Action[] memory actions = new IDAO.Action[](3);
        actions[0] = IDAO.Action({
            to: config.dao,
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (config.vetoReceiver, config.dao, setAggregatorPermission))
        });
        actions[1] = IDAO.Action({
            to: config.plugin,
            value: 0,
            data: abi.encodeCall(OptimisticTokenVotingPlugin.setL2VetoReceiver, (config.vetoReceiver))
        });
        actions[2] = IDAO.Action({
            to: config.vetoReceiver,
            value: 0,
            data: abi.encodeCall(L2VetoReceiver.setTrustedL2Aggregator, (config.vetoAggregator))
        });

        _writeProposal("proposal-configure-l2-veto", actions);
        _logActions(actions);
    }

    function _loadConfig() internal view returns (Config memory) {
        return Config({
            dao: vm.envAddress("DAO_ADDRESS"),
            plugin: vm.envAddress("PLUGIN_ADDRESS"),
            vetoReceiver: vm.envAddress("VETO_RECEIVER_ADDRESS"),
            vetoAggregator: vm.envAddress("VETO_AGGREGATOR_ADDRESS")
        });
    }
}
