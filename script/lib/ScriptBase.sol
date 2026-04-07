// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

abstract contract ScriptBase is Script {
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

    function _logActions(IDAO.Action[] memory _actions) internal view {
        console.log("Proposal actions:");
        for (uint256 i = 0; i < _actions.length; i++) {
            console.log("  Action %d: to=%s", i, _actions[i].to);
            console.log("    data=%s", vm.toString(_actions[i].data));
        }
    }

    function _writeProposal(string memory _filename, IDAO.Action[] memory _actions) internal {
        string memory dir = string.concat(vm.projectRoot(), "/proposals");
        vm.createDir(dir, true);
        vm.writeFile(string.concat(dir, "/", _filename), _serializeActions(_actions));
        console.log("Wrote proposals/%s", _filename);
    }
}
