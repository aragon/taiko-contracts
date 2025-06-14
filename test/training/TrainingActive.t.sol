// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AragonTest} from "../base/AragonTest.sol";
import "../../src/training/TrainingActive.sol";

contract TrainingActiveTest is AragonTest {
    TrainingActive base;

    address immutable DAO_ADDRESS = address(0x123);

    function setUp() public {
        vm.prank(alice);
        base = new TrainingActive(DAO_ADDRESS);
    }

    function test_revert_disableIfNotOwner() public {
        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        base.disable();
    }

    function test_disable() public {
        vm.prank(DAO_ADDRESS);
        base.disable();
        assertTrue(base.disabled());
    }

    function test_revert_disableIfAlreadyDisabled() public {
        vm.prank(DAO_ADDRESS);
        base.disable();
        vm.expectRevert("Ownable: caller is not the owner");
        base.disable();
    }
}
