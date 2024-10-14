// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {EncryptionRegistry} from "../src/EncryptionRegistry.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../src/Multisig.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract EncryptionRegistryTest is AragonTest {
    EncryptionRegistry registry;
    DaoBuilder builder;
    DAO dao;
    Multisig multisig;

    // Events/errors to be tested here (duplicate)
    event PublicKeySet(address member, bytes32 publicKey);
    event WalletAppointed(address member, address appointedWallet);

    function setUp() public {
        builder = new DaoBuilder();
        (dao,, multisig,,,) = builder.withMultisigMember(alice).withMultisigMember(bob).withMultisigMember(carol)
            .withMultisigMember(david).build();

        registry = new EncryptionRegistry(multisig);
    }

    function test_ShouldAppointWallets() public {
        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.appointWallet(address(0x1234000000000000000000000000000000000000));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));

        // Bob
        vm.startPrank(bob);
        registry.appointWallet(address(0x0000567800000000000000000000000000000000));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(0x0000000090aB0000000000000000000000000000));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000000090aB0000000000000000000000000000));

        // David
        vm.startPrank(david);
        registry.appointWallet(address(0x000000000000cdEf000000000000000000000000));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000000090aB0000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(david);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x000000000000cdEf000000000000000000000000));
    }

    function test_ShouldRegisterOwnPublicKeys() public {
        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(david);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function testFuzz_ShouldRegisterMemberPublicKeys(address appointedWallet) public {
        if (Address.isContract(appointedWallet)) return;

        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.appointWallet(appointedWallet);
        vm.startPrank(appointedWallet);
        registry.setPublicKey(alice, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.appointWallet(appointedWallet);
        vm.startPrank(appointedWallet);
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(appointedWallet);
        vm.startPrank(appointedWallet);
        registry.setPublicKey(carol, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.appointWallet(appointedWallet);
        vm.startPrank(appointedWallet);
        registry.setPublicKey(david, 0x000000000000cdef000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(david);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function test_ShouldClearPublicKeyAfterAppointing(address appointedWallet) public {
        if (appointedWallet == address(0)) return;
        else if (Address.isContract(appointedWallet)) return;

        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(alice);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(appointedWallet);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(appointedWallet);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        registry.appointWallet(appointedWallet);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(david);
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);

        registry.appointWallet(appointedWallet);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(david);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldRevertWhenAppointingContracts() public {
        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        vm.startPrank(alice);

        // OK
        registry.appointWallet(address(0x1234));
        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0x1234));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // OK
        registry.appointWallet(bob);
        registry.appointWallet(carol);
        registry.appointWallet(david);

        // KO
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.CannotAppointContracts.selector));
        registry.appointWallet(address(dao));
        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, david);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // KO
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.CannotAppointContracts.selector));
        registry.appointWallet(address(multisig));
        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, david);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // KO
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.CannotAppointContracts.selector));
        registry.appointWallet(address(registry));
        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, david);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldRevertIfNotListed(address appointedWallet) public {
        if (Address.isContract(appointedWallet)) return;

        address addrValue;
        bytes32 bytesValue;

        // Only Alice
        (,, multisig,,,) = new DaoBuilder().withMultisigMember(alice).build();
        registry = new EncryptionRegistry(multisig);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // OK

        // Alice
        vm.startPrank(alice);
        assertEq(multisig.isMember(alice), true);
        registry.setOwnPublicKey(0x5678000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x5678000000000000000000000000000000000000000000000000000000000000);

        // Appoint self
        registry.appointWallet(alice);
        vm.startPrank(alice);
        registry.setPublicKey(alice, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // NOT OK

        // Bob
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.appointWallet(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.startPrank(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.setPublicKey(bob, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.appointWallet(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.startPrank(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.setPublicKey(carol, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.appointWallet(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.startPrank(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.setPublicKey(david, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(david);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldRevertOnSetPublicKeyIfNotAppointed(address appointedWallet) public {
        if (Address.isContract(appointedWallet)) return;

        address addrValue;
        bytes32 bytesValue;

        // Alice
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.NotAppointed.selector));
        registry.setPublicKey(alice, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(appointedWallet);

        // Appointed
        vm.startPrank(appointedWallet);
        registry.setPublicKey(alice, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.NotAppointed.selector));
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(appointedWallet);

        // Appointed
        vm.startPrank(appointedWallet);
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldRevertIfOwnerNotAppointed(address appointedWallet) public {
        if (appointedWallet == address(0)) return;
        else if (Address.isContract(appointedWallet)) return;

        address addrValue;
        bytes32 bytesValue;

        // Alice
        vm.startPrank(alice);
        registry.appointWallet(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.OwnerNotAppointed.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Appointed
        registry.appointWallet(alice);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.appointWallet(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.OwnerNotAppointed.selector));
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Appointed
        registry.appointWallet(bob);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, bob);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldEmitPublicKeyDefinedEvents() public {
        // For itself
        vm.startPrank(alice);
        vm.expectEmit();
        emit PublicKeySet(alice, 0x000000000000cdef000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        vm.startPrank(bob);
        vm.expectEmit();
        emit PublicKeySet(bob, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        vm.startPrank(carol);
        vm.expectEmit();
        emit PublicKeySet(carol, 0x0000567800000000000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        vm.startPrank(david);
        vm.expectEmit();
        emit PublicKeySet(david, 0x1234000000000000000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        // As the appointee
        vm.startPrank(alice);
        registry.appointWallet(alice); // Self
        vm.expectEmit();
        emit PublicKeySet(alice, 0x0000000000000000cdef00000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x0000000000000000cdef00000000000000000000000000000000000000000000);

        vm.startPrank(bob);
        registry.appointWallet(bob); // Self
        vm.expectEmit();
        emit PublicKeySet(bob, 0x00000000000090ab000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x00000000000090ab000000000000000000000000000000000000000000000000);

        vm.startPrank(carol);
        registry.appointWallet(carol); // Self
        vm.expectEmit();
        emit PublicKeySet(carol, 0x0000000056780000000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x0000000056780000000000000000000000000000000000000000000000000000);

        vm.startPrank(david);
        registry.appointWallet(david); // Self
        vm.expectEmit();
        emit PublicKeySet(david, 0x0000123400000000000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x0000123400000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldCountRegisteredAddresses() public {
        assertEq(registry.getRegisteredAddressesLength(), 0, "Incorrect count");

        // Set public key first

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        assertEq(registry.getRegisteredAddressesLength(), 1, "Incorrect count");
        registry.appointWallet(address(0x1234));
        assertEq(registry.getRegisteredAddressesLength(), 1, "Incorrect count");

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.getRegisteredAddressesLength(), 2, "Incorrect count");
        registry.appointWallet(address(0x5678));
        assertEq(registry.getRegisteredAddressesLength(), 2, "Incorrect count");

        // Appoint first

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(0x90ab));
        assertEq(registry.getRegisteredAddressesLength(), 3, "Incorrect count");
        registry.appointWallet(carol);
        registry.setPublicKey(carol, bytes32(uint256(3456)));
        assertEq(registry.getRegisteredAddressesLength(), 3, "Incorrect count");

        // David
        vm.startPrank(david);
        registry.appointWallet(address(0xcdef));
        assertEq(registry.getRegisteredAddressesLength(), 4, "Incorrect count");
        registry.appointWallet(david);
        registry.setPublicKey(david, bytes32(uint256(4567)));
        assertEq(registry.getRegisteredAddressesLength(), 4, "Incorrect count");
    }

    function test_ShouldEnumerateRegisteredAddresses() public {
        // Set public key first

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        assertEq(registry.registeredAddresses(0), alice);
        registry.appointWallet(address(0x1234));
        assertEq(registry.registeredAddresses(0), alice);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.registeredAddresses(1), bob);
        registry.appointWallet(address(0x5678));
        assertEq(registry.registeredAddresses(1), bob);

        // Appoint first

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(0x90ab));
        assertEq(registry.registeredAddresses(2), carol);
        registry.appointWallet(carol);
        registry.setPublicKey(carol, bytes32(uint256(3456)));
        assertEq(registry.registeredAddresses(2), carol);

        // David
        vm.startPrank(david);
        registry.appointWallet(address(0xcdef));
        assertEq(registry.registeredAddresses(3), david);
        registry.appointWallet(david);
        registry.setPublicKey(david, bytes32(uint256(4567)));
        assertEq(registry.registeredAddresses(3), david);

        assertEq(registry.getRegisteredAddressesLength(), 4, "Incorrect count");

        assertEq(registry.registeredAddresses(0), alice);
        assertEq(registry.registeredAddresses(1), bob);
        assertEq(registry.registeredAddresses(2), carol);
        assertEq(registry.registeredAddresses(3), david);
    }

    function test_ShouldLoadTheRegisteredAddresses() public {
        // Set public key first

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        assertEq(registry.registeredAddresses(0), alice);
        registry.appointWallet(address(0x1234));
        assertEq(registry.registeredAddresses(0), alice);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.registeredAddresses(1), bob);
        registry.appointWallet(address(0x5678));
        assertEq(registry.registeredAddresses(1), bob);

        // Appoint first

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(0x90ab));
        assertEq(registry.registeredAddresses(2), carol);
        registry.appointWallet(carol);
        registry.setPublicKey(carol, bytes32(uint256(3456)));
        assertEq(registry.registeredAddresses(2), carol);

        // David
        vm.startPrank(david);
        registry.appointWallet(address(0xcdef));
        assertEq(registry.registeredAddresses(3), david);
        registry.appointWallet(david);
        registry.setPublicKey(david, bytes32(uint256(4567)));
        assertEq(registry.registeredAddresses(3), david);

        address[] memory addresses = registry.getRegisteredAddresses();
        assertEq(addresses.length, 4);
        assertEq(addresses[0], alice);
        assertEq(addresses[1], bob);
        assertEq(addresses[2], carol);
        assertEq(addresses[3], david);
    }

    function test_TheConstructorShouldRevertIfInvalidAddressList() public {
        // Fail
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.InvalidAddressList.selector));
        new EncryptionRegistry(Addresslist(address(this)));

        // OK
        (,, multisig,,,) = new DaoBuilder().withMultisigMember(alice).build();
        new EncryptionRegistry(multisig);
    }

    /// @dev mock function for test_TheConstructorShouldRevertIfInvalidAddressList()
    function supportsInterface(bytes4) public pure returns (bool) {
        return false;
    }
}
