// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {L2VetoReceiver} from "../src/crosschain/L2VetoReceiver.sol";

/// @title ConfigureL2Veto
/// @notice Generates a proposal JSON to wire L2VetoReceiver + L2VetoAggregator into the plugin.
contract ConfigureL2Veto is Script {
    function run() external {
        address dao = vm.envAddress("DAO_ADDRESS");
        address plugin = vm.envAddress("PLUGIN_ADDRESS");
        address l2VetoReceiver = vm.envAddress("L2_VETO_RECEIVER_ADDRESS");
        address aggregator = vm.envAddress("L2_VETO_AGGREGATOR_ADDRESS");

        console.log("Generating L2 veto configuration proposal");
        console.log("  DAO:", dao);
        console.log("  Plugin:", plugin);
        console.log("  L2VetoReceiver:", l2VetoReceiver);
        console.log("  L2VetoAggregator:", aggregator);

        bytes32 setAggregatorPermission = L2VetoReceiver(l2VetoReceiver).SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID();

        // Action 1: Grant DAO permission to set trusted aggregator on receiver
        bytes memory data0 = abi.encodeCall(PermissionManager.grant, (l2VetoReceiver, dao, setAggregatorPermission));

        // Action 2: Set L2VetoReceiver on the plugin
        bytes memory data1 = abi.encodeCall(OptimisticTokenVotingPlugin.setL2VetoReceiver, (l2VetoReceiver));

        // Action 3: Set trusted L2 aggregator on the receiver
        bytes memory data2 = abi.encodeCall(L2VetoReceiver.setTrustedL2Aggregator, (aggregator));

        // Build the JSON array
        string memory json = string.concat(
            "[\n",
            '  {"to":"', vm.toString(dao), '","value":0,"data":"', vm.toString(data0), '"},\n',
            '  {"to":"', vm.toString(plugin), '","value":0,"data":"', vm.toString(data1), '"},\n',
            '  {"to":"', vm.toString(l2VetoReceiver), '","value":0,"data":"', vm.toString(data2), '"}\n',
            "]"
        );

        string memory dir = string.concat(vm.projectRoot(), "/proposals");
        vm.createDir(dir, true);
        vm.writeFile(string.concat(dir, "/proposal-configure-l2-veto.json"), json);
        console.log("Wrote proposals/proposal-configure-l2-veto.json");
    }
}
