// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

abstract contract HandlerBase is Test {
    address public immutable testBaseAddr;

    constructor(address _testBase) {
        testBaseAddr = _testBase;
    }

    function printHandlerStatistics() public view virtual;

    function _printStat(string memory label, uint256 value) internal pure {
        console.log(string.concat("  ", label, ": ", vm.toString(value)));
    }

    function _printSection(string memory title) internal pure {
        console.log("");
        console.log(string.concat("[", title, "]"));
    }
}
