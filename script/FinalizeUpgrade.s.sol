// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {L2VetoReceiver} from "../src/crosschain/L2VetoReceiver.sol";

/// @title FinalizeUpgrade
/// @notice Generates the finalize DAO proposal action (proposal-2-finalize.json).
/// @dev Run after deploying L2VetoAggregator on L2.
///      After upgrade(), the DAO has SET_TRUSTED_L2_AGGREGATOR_PERMISSION on the receiver,
///      so the DAO can set the aggregator directly — no factory or ROOT re-grant needed.
///      Requires: DAO_ADDRESS, L2_VETO_RECEIVER_ADDRESS, L2_VETO_AGGREGATOR_ADDRESS
contract FinalizeUpgrade is Script {
    function run() external {
        address l2VetoReceiver = vm.envAddress("L2_VETO_RECEIVER_ADDRESS");
        address aggregator = vm.envAddress("L2_VETO_AGGREGATOR_ADDRESS");

        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0] = IDAO.Action({
            to: l2VetoReceiver,
            value: 0,
            data: abi.encodeCall(L2VetoReceiver.setTrustedL2Aggregator, (aggregator))
        });

        string memory dir = string.concat(vm.projectRoot(), "/proposals");
        vm.createDir(dir, true);
        string memory path = string.concat(dir, "/proposal-2-finalize.json");
        vm.writeFile(path, _serializeActions(actions));
        console.log("Wrote proposals/proposal-2-finalize.json");
        console.log("  Action: l2VetoReceiver.setTrustedL2Aggregator(%s)", aggregator);
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
