// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {
    UpgradeOptimisticTokenVotingPluginFactory
} from "../src/factory/UpgradeOptimisticTokenVotingPluginFactory.sol";

/// @title FinalizeUpgrade
/// @notice Generates the finalize DAO proposal actions (proposal-2-finalize.json).
/// @dev Run after deploying L2VetoAggregator on L2.
///      Requires: DAO_ADDRESS, FACTORY_ADDRESS, L2_VETO_RECEIVER_ADDRESS, L2_VETO_AGGREGATOR_ADDRESS
contract FinalizeUpgrade is Script {
    function run() external {
        address dao = vm.envAddress("DAO_ADDRESS");
        address factory = vm.envAddress("FACTORY_ADDRESS");
        address l2VetoReceiver = vm.envAddress("L2_VETO_RECEIVER_ADDRESS");
        address aggregator = vm.envAddress("L2_VETO_AGGREGATOR_ADDRESS");

        bytes32 rootPermission = DAO(payable(dao)).ROOT_PERMISSION_ID();

        IDAO.Action[] memory actions = new IDAO.Action[](2);
        actions[0] = IDAO.Action({
            to: dao,
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (dao, factory, rootPermission))
        });
        actions[1] = IDAO.Action({
            to: factory,
            value: 0,
            data: abi.encodeCall(
                UpgradeOptimisticTokenVotingPluginFactory.finalize,
                (DAO(payable(dao)), l2VetoReceiver, aggregator)
            )
        });

        string memory dir = string.concat(vm.projectRoot(), "/proposals");
        vm.createDir(dir, true);
        string memory path = string.concat(dir, "/proposal-2-finalize.json");
        vm.writeFile(path, _serializeActions(actions));
        console.log("Wrote proposals/proposal-2-finalize.json");
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
