// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AragonTest} from "../base/AragonTest.sol";
import "../../src/training/TrainingPingPong.sol";
import "../../src/training/TrainingActive.sol";

contract TrainingPingPongTest is AragonTest {
    TrainingPingPong base;

    address immutable DAO_ADDRESS = address(0x123);

    function setUp() public {
        vm.prank(alice);
        base = new TrainingPingPong(DAO_ADDRESS);
    }

    function test_ping_revertIfNotOwner() public {
        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        base.ping();
    }

    function test_ping_revertIfNotActive() public {
        vm.prank(DAO_ADDRESS);
        base.disable();
        vm.expectRevert(TrainingActive.AlreadyDisabled.selector);
        base.ping();
    }

    function test_ping() public {
        assertEq(base.pingCount(), 0);
        vm.prank(DAO_ADDRESS);
        base.ping();
        assertEq(base.pingCount(), 1);
    }
}
