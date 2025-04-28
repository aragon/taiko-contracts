// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AragonTest} from "../base/AragonTest.sol";
import "../../src/training/TrainingToken.sol";
import "../../src/training/TrainingActive.sol";

contract TrainingTokenTest is AragonTest {
    TrainingToken token;

    address immutable DAO_ADDRESS = address(0x123);
    uint256 public totalSupply;

    function setUp() public {
        vm.prank(alice);
        token = new TrainingToken(DAO_ADDRESS);
        totalSupply = token.totalSupply();
    }

    function test_fundsMinted() public view {
        assertEq(token.balanceOf(DAO_ADDRESS), totalSupply);
    }

    function test_transferBackFromDao() public {
        vm.prank(DAO_ADDRESS);
        token.transfer(address(token), 100);
        assertEq(token.balanceOf(DAO_ADDRESS), totalSupply - 100);
        // ensure transferred funds are burnt
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), totalSupply - 100);
    }

    function test_revert_transferToAnotherAccount() public {
        vm.prank(DAO_ADDRESS);
        vm.expectRevert(TrainingToken.ReceiverNotAllowed.selector);
        token.transfer(address(0xabc), 100);
    }

    function test_disable() public {
        vm.prank(DAO_ADDRESS);
        token.disable();
        assertTrue(token.disabled());
        // ensure all balances are burnt
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(DAO_ADDRESS), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
