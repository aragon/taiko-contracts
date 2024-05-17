// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {PublicKeyRegistry} from "../src/PublicKeyRegistry.sol";
import {createProxyAndCall} from "./helpers/proxy.sol";

contract EmergencyMultisigTest is AragonTest {
    PublicKeyRegistry registry;

    // Events/errors to be tested here (duplicate)
    event PublicKeyRegistered(address wallet, bytes32 publicKey);

    error AlreadySet();

    function setUp() public {
        registry = new PublicKeyRegistry();
    }

    function test_ShouldRegisterAPublicKey() public {
        assertEq(registry.getPublicKey(alice), 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        switchTo(alice);
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        assertEq(registry.getPublicKey(alice), 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        switchTo(bob);
        registry.setPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        assertEq(registry.getPublicKey(alice), 0x1234000000000000000000000000000000000000000000000000000000000000);
        assertEq(registry.getPublicKey(bob), 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        switchTo(carol);
        registry.setPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        assertEq(registry.getPublicKey(alice), 0x1234000000000000000000000000000000000000000000000000000000000000);
        assertEq(registry.getPublicKey(bob), 0x0000567800000000000000000000000000000000000000000000000000000000);
        assertEq(registry.getPublicKey(carol), 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        switchTo(david);
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        assertEq(registry.getPublicKey(alice), 0x1234000000000000000000000000000000000000000000000000000000000000);
        assertEq(registry.getPublicKey(bob), 0x0000567800000000000000000000000000000000000000000000000000000000);
        assertEq(registry.getPublicKey(carol), 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        assertEq(registry.getPublicKey(david), 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function test_ShouldEmitARegistrationEvent() public {
        switchTo(alice);
        vm.expectEmit();
        emit PublicKeyRegistered(alice, 0x000000000000cdef000000000000000000000000000000000000000000000000);
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        switchTo(bob);
        vm.expectEmit();
        emit PublicKeyRegistered(bob, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        registry.setPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        switchTo(carol);
        vm.expectEmit();
        emit PublicKeyRegistered(carol, 0x0000567800000000000000000000000000000000000000000000000000000000);
        registry.setPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        switchTo(david);
        vm.expectEmit();
        emit PublicKeyRegistered(david, 0x1234000000000000000000000000000000000000000000000000000000000000);
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldRevertIfReRegistering() public {
        switchTo(alice);
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        switchTo(bob);
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        switchTo(carol);
        registry.setPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        switchTo(david);
        registry.setPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
    }
}
