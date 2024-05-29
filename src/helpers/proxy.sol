// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

function createProxyAndCall(address _logic, bytes memory _data) returns (address) {
    return address(new ERC1967Proxy(_logic, _data));
}
