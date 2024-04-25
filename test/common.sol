// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

bytes32 constant PROPOSER_PERMISSION_ID = keccak256("PROPOSER_PERMISSION");
bytes32 constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
bytes32 constant UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID = keccak256(
    "UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION"
);
bytes32 constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256(
    "UPGRADE_PLUGIN_PERMISSION"
);
bytes32 constant ROOT_PERMISSION_ID = keccak256("ROOT_PERMISSION");

uint64 constant MAX_UINT64 = uint64(2 ** 64 - 1);
address constant ADDRESS_ZERO = address(0x0);
address constant NO_CONDITION = ADDRESS_ZERO;

// HELPERS

function createProxyAndCall(
    address _logic,
    bytes memory _data
) returns (address) {
    return address(new ERC1967Proxy(_logic, _data));
}
