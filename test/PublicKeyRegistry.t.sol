// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {PublicKeyRegistry} from "../src/PublicKeyRegistry.sol";
import {createProxyAndCall} from "../src/helpers/proxy.sol";

contract EmergencyMultisigTest is AragonTest {
    PublicKeyRegistry registry;

    // Events/errors to be tested here (duplicate)
    event PublicKeyRegistered(address wallet, bytes32 publicKey);

    error AlreadySet();

    function setUp() public {
        registry = new PublicKeyRegistry();
    }

    function test_ShouldRegisterAPublicKey() public {
        assertEq(registry.publicKeys(alice), 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        assertEq(registry.publicKeys(alice), 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.setPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        assertEq(registry.publicKeys(alice), 0x1234000000000000000000000000000000000000000000000000000000000000);
        assertEq(registry.publicKeys(bob), 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.setPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        assertEq(registry.publicKeys(alice), 0x1234000000000000000000000000000000000000000000000000000000000000);
        assertEq(registry.publicKeys(bob), 0x0000567800000000000000000000000000000000000000000000000000000000);
        assertEq(registry.publicKeys(carol), 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        assertEq(registry.publicKeys(alice), 0x1234000000000000000000000000000000000000000000000000000000000000);
        assertEq(registry.publicKeys(bob), 0x0000567800000000000000000000000000000000000000000000000000000000);
        assertEq(registry.publicKeys(carol), 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        assertEq(registry.publicKeys(david), 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function test_ShouldEmitARegistrationEvent() public {
        vm.startPrank(alice);
        vm.expectEmit();
        emit PublicKeyRegistered(alice, 0x000000000000cdef000000000000000000000000000000000000000000000000);
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        vm.startPrank(bob);
        vm.expectEmit();
        emit PublicKeyRegistered(bob, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        registry.setPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        vm.startPrank(carol);
        vm.expectEmit();
        emit PublicKeyRegistered(carol, 0x0000567800000000000000000000000000000000000000000000000000000000);
        registry.setPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        vm.startPrank(david);
        vm.expectEmit();
        emit PublicKeyRegistered(david, 0x1234000000000000000000000000000000000000000000000000000000000000);
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldRevertIfReRegistering() public {
        vm.startPrank(alice);
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        vm.startPrank(bob);
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        vm.startPrank(carol);
        registry.setPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        vm.startPrank(david);
        registry.setPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.expectRevert(abi.encodeWithSelector(AlreadySet.selector));
        registry.setPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function test_ShouldCountRegisteredCandidates() public {
        assertEq(registry.registeredWalletCount(), 0, "Incorrect count");

        // Alice
        vm.startPrank(alice);
        registry.setPublicKey(bytes32(uint256(1234)));
        assertEq(registry.registeredWalletCount(), 1, "Incorrect count");

        // Bob
        vm.startPrank(bob);
        registry.setPublicKey(bytes32(uint256(2345)));
        assertEq(registry.registeredWalletCount(), 2, "Incorrect count");

        // Carol
        vm.startPrank(carol);
        registry.setPublicKey(bytes32(uint256(3456)));
        assertEq(registry.registeredWalletCount(), 3, "Incorrect count");

        // David
        vm.startPrank(david);
        registry.setPublicKey(bytes32(uint256(4567)));
        assertEq(registry.registeredWalletCount(), 4, "Incorrect count");
    }

    function test_ShouldEnumerateRegisteredCandidates() public {
        // Register
        vm.startPrank(alice);
        registry.setPublicKey(bytes32(uint256(1234)));
        vm.startPrank(bob);
        registry.setPublicKey(bytes32(uint256(2345)));
        vm.startPrank(carol);
        registry.setPublicKey(bytes32(uint256(3456)));
        vm.startPrank(david);
        registry.setPublicKey(bytes32(uint256(4567)));

        assertEq(registry.registeredWalletCount(), 4, "Incorrect count");

        assertEq(registry.registeredWallets(0), alice);
        assertEq(registry.registeredWallets(1), bob);
        assertEq(registry.registeredWallets(2), carol);
        assertEq(registry.registeredWallets(3), david);
    }

    function test_ShouldLoadTheRegisteredAddresses() public {
        vm.startPrank(alice);
        registry.setPublicKey(bytes32(uint256(1234)));
        vm.startPrank(bob);
        registry.setPublicKey(bytes32(uint256(2345)));
        vm.startPrank(carol);
        registry.setPublicKey(bytes32(uint256(3456)));
        vm.startPrank(david);
        registry.setPublicKey(bytes32(uint256(4567)));

        address[] memory candidates = registry.getRegisteredWallets();
        assertEq(candidates.length, 4);
        assertEq(candidates[0], alice);
        assertEq(candidates[1], bob);
        assertEq(candidates[2], carol);
        assertEq(candidates[3], david);
    }
}
