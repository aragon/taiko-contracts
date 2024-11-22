// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {EncryptionRegistry, IEncryptionRegistry} from "../src/EncryptionRegistry.sol";
import {SignerList} from "../src/SignerList.sol";
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
        (dao,, multisig,,,, registry,) = builder.withMultisigMember(alice).withMultisigMember(bob).withMultisigMember(
            carol
        ).withMultisigMember(david).build();
    }

    function test_ShouldAppointWallets() public {
        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.appointWallet(address(0x1234000000000000000000000000000000000000));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));

        // Bob
        vm.startPrank(bob);
        registry.appointWallet(address(0x0000567800000000000000000000000000000000));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(0x0000000090aB0000000000000000000000000000));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000000090aB0000000000000000000000000000));

        // David
        vm.startPrank(david);
        registry.appointWallet(address(0x000000000000cdEf000000000000000000000000));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000000090aB0000000000000000000000000000));
        (addrValue, bytesValue) = registry.accounts(david);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x000000000000cdEf000000000000000000000000));
    }

    function test_ShouldRegisterOwnPublicKeys() public {
        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(david);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function testFuzz_ShouldRegisterMemberPublicKeys(address appointedWallet) public {
        if (skipAppointedWallet(appointedWallet)) return;

        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.appointWallet(appointedWallet);
        vm.startPrank(appointedWallet);
        registry.setPublicKey(alice, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.appointWallet(address(uint160(appointedWallet) + 100));
        vm.startPrank(address(uint160(appointedWallet) + 100));
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedWallet) + 100));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(uint160(appointedWallet) + 200));
        vm.startPrank(address(uint160(appointedWallet) + 200));
        registry.setPublicKey(carol, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedWallet) + 100));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(uint160(appointedWallet) + 200));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.appointWallet(address(uint160(appointedWallet) + 300));
        vm.startPrank(address(uint160(appointedWallet) + 300));
        registry.setPublicKey(david, 0x000000000000cdef000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedWallet) + 100));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(uint160(appointedWallet) + 200));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(david);
        assertEq(addrValue, address(uint160(appointedWallet) + 300));
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function testFuzz_ShouldClearPublicKeyAfterAppointing(address appointedWallet) public {
        if (skipAppointedWallet(appointedWallet)) return;

        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(appointedWallet);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(address(uint160(appointedWallet) + 100));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedWallet) + 100));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        registry.appointWallet(address(uint160(appointedWallet) + 200));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedWallet) + 100));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(uint160(appointedWallet) + 200));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(david);
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);

        registry.appointWallet(address(uint160(appointedWallet) + 300));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedWallet) + 100));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(uint160(appointedWallet) + 200));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(david);
        assertEq(addrValue, address(uint160(appointedWallet) + 300));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldRevertWhenAppointingContracts() public {
        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        vm.startPrank(alice);

        // OK
        registry.appointWallet(address(0x1234));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1234));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // OK
        registry.appointWallet(address(0x1111));
        registry.appointWallet(address(0x2222));
        registry.appointWallet(address(0x3333));

        // KO
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.CannotAppointContracts.selector));
        registry.appointWallet(address(dao));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x3333));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // KO
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.CannotAppointContracts.selector));
        registry.appointWallet(address(multisig));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x3333));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // KO
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.CannotAppointContracts.selector));
        registry.appointWallet(address(registry));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x3333));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
    }

    function test_shouldAllowToAppointBackAndForth() public {
        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        vm.startPrank(alice);

        // Neutral
        registry.appointWallet(address(0x0));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Repeated appointments
        registry.appointWallet(address(0x1234));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1234));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(address(0x1234));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1234));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Bob
        registry.appointWallet(address(0x1111));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1111));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(address(0x1111));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1111));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(address(0x1111));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1111));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // More
        registry.appointWallet(address(0x2222));
        registry.appointWallet(address(0x2222));
        registry.appointWallet(address(0x2222));

        registry.appointWallet(address(0x3333));
        registry.appointWallet(address(0x3333));
        registry.appointWallet(address(0x3333));

        // OK again
        registry.appointWallet(address(0x1234));
        registry.appointWallet(address(0x1111));
        registry.appointWallet(address(0x2222));
        registry.appointWallet(address(0x3333));
    }

    function test_getRegisteredAccountsOnlyReturnsAddressesOnce() public {
        uint256 count = registry.getRegisteredAccounts().length;
        assertEq(count, 0);

        vm.startPrank(alice);

        // Neutral
        registry.appointWallet(address(0x0));

        count = registry.getRegisteredAccounts().length;
        assertEq(count, 0);

        // Appoint
        registry.appointWallet(address(0x1111));

        count = registry.getRegisteredAccounts().length;
        assertEq(count, 1);

        registry.appointWallet(address(0x2222));

        count = registry.getRegisteredAccounts().length;
        assertEq(count, 1);

        registry.appointWallet(address(0x3333));

        count = registry.getRegisteredAccounts().length;
        assertEq(count, 1);
    }

    function test_shouldRevertIfAppointingAnotherSigner() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointWallet(bob);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointWallet(carol);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointWallet(david);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointWallet(alice);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointWallet(carol);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointWallet(david);

        // ok
        registry.appointWallet(address(0x5555));
    }

    function test_shouldRevertWhenAlreadyAppointed() public {
        vm.startPrank(alice);
        registry.appointWallet(address(0x1234));

        vm.startPrank(bob);
        registry.appointWallet(address(0x2345));

        // Fail
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyAppointed.selector));
        registry.appointWallet(address(0x2345));

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyAppointed.selector));
        registry.appointWallet(address(0x1234));

        // ok
        registry.appointWallet(address(0x5555));
    }

    function testFuzz_AppointShouldRevertIfNotListed(address appointedWallet) public {
        if (Address.isContract(appointedWallet)) return;

        SignerList signerList;
        address addrValue;
        bytes32 bytesValue;

        // Only Alice
        (,, multisig,,, signerList, registry,) = new DaoBuilder().withMultisigMember(alice).build();
        if (signerList.isListed(appointedWallet)) return;

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // OK

        // Alice
        vm.startPrank(alice);
        assertEq(signerList.isListed(alice), true);
        registry.setOwnPublicKey(0x5678000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x5678000000000000000000000000000000000000000000000000000000000000);

        // Appoint self
        registry.appointWallet(appointedWallet);
        vm.startPrank(appointedWallet);
        registry.setPublicKey(alice, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // NOT OK

        // Bob
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.appointWallet(address(uint160(appointedWallet) + 100));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.startPrank(address(uint160(appointedWallet) + 100));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setPublicKey(bob, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.appointWallet(address(uint160(appointedWallet) + 200));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.startPrank(address(uint160(appointedWallet) + 200));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setPublicKey(carol, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.appointWallet(address(uint160(appointedWallet) + 300));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.startPrank(address(uint160(appointedWallet) + 300));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setPublicKey(david, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(david);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
    }

    function testFuzz_ShouldRevertOnSetPublicKeyIfNotAppointed(address appointedWallet) public {
        if (skipAppointedWallet(appointedWallet)) return;

        address addrValue;
        bytes32 bytesValue;

        // Alice
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeAppointed.selector));
        registry.setPublicKey(alice, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(appointedWallet);

        // Appointed
        vm.startPrank(appointedWallet);
        registry.setPublicKey(alice, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeAppointed.selector));
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointWallet(address(uint160(appointedWallet) + 100));

        // Appointed
        vm.startPrank(address(uint160(appointedWallet) + 100));
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedWallet) + 100));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
    }

    function testFuzz_ShouldRevertOnSetOwnPublicKeyIfOwnerIsAppointing(address appointedWallet) public {
        if (skipAppointedWallet(appointedWallet)) return;

        address addrValue;
        bytes32 bytesValue;

        // Alice
        vm.startPrank(alice);
        registry.appointWallet(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustResetAppointment.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Appointed
        registry.appointWallet(alice);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.appointWallet(appointedWallet);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustResetAppointment.selector));
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Appointed
        registry.appointWallet(bob);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
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

    function test_RegisteredAddressShouldHaveTheRightLength() public {
        assertEq(registry.getRegisteredAccounts().length, 0, "Incorrect length");

        // Set public key first

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect length");
        registry.appointWallet(address(0x1234));
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect length");

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect length");
        registry.appointWallet(address(0x5678));
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect length");

        // Appoint first

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(0x90ab));
        assertEq(registry.getRegisteredAccounts().length, 3, "Incorrect length");
        registry.appointWallet(address(0x6666));
        vm.startPrank(address(0x6666));
        registry.setPublicKey(carol, bytes32(uint256(3456)));
        assertEq(registry.getRegisteredAccounts().length, 3, "Incorrect length");

        // David
        vm.startPrank(david);
        registry.appointWallet(address(0xcdef));
        assertEq(registry.getRegisteredAccounts().length, 4, "Incorrect length");
        registry.appointWallet(address(0x7777));
        vm.startPrank(address(0x7777));
        registry.setPublicKey(david, bytes32(uint256(4567)));
        assertEq(registry.getRegisteredAccounts().length, 4, "Incorrect length");
    }

    function test_ShouldEnumerateRegisteredAddresses() public {
        // Set public key first

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        assertEq(registry.registeredAccounts(0), alice);
        registry.appointWallet(address(0x1234));
        assertEq(registry.registeredAccounts(0), alice);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.registeredAccounts(1), bob);
        registry.appointWallet(address(0x5678));
        assertEq(registry.registeredAccounts(1), bob);

        // Appoint first

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(0x90ab));
        assertEq(registry.registeredAccounts(2), carol);
        registry.appointWallet(address(0x6666));
        vm.startPrank(address(0x6666));
        registry.setPublicKey(carol, bytes32(uint256(3456)));
        assertEq(registry.registeredAccounts(2), carol);

        // David
        vm.startPrank(david);
        registry.appointWallet(address(0xcdef));
        assertEq(registry.registeredAccounts(3), david);
        registry.appointWallet(address(0x7777));
        vm.startPrank(address(0x7777));
        registry.setPublicKey(david, bytes32(uint256(4567)));
        assertEq(registry.registeredAccounts(3), david);

        assertEq(registry.getRegisteredAccounts().length, 4, "Incorrect length");

        assertEq(registry.registeredAccounts(0), alice);
        assertEq(registry.registeredAccounts(1), bob);
        assertEq(registry.registeredAccounts(2), carol);
        assertEq(registry.registeredAccounts(3), david);
    }

    function test_ShouldLoadTheRegisteredAddresses() public {
        // Set public key first

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        assertEq(registry.registeredAccounts(0), alice);
        registry.appointWallet(address(0x1234));
        assertEq(registry.registeredAccounts(0), alice);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.registeredAccounts(1), bob);
        registry.appointWallet(address(0x5678));
        assertEq(registry.registeredAccounts(1), bob);

        // Appoint first

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(0x90ab));
        assertEq(registry.registeredAccounts(2), carol);
        registry.appointWallet(address(0x6666));
        vm.startPrank(address(0x6666));
        registry.setPublicKey(carol, bytes32(uint256(3456)));
        assertEq(registry.registeredAccounts(2), carol);

        // David
        vm.startPrank(david);
        registry.appointWallet(address(0xcdef));
        assertEq(registry.registeredAccounts(3), david);
        registry.appointWallet(address(0x7777));
        vm.startPrank(address(0x7777));
        registry.setPublicKey(david, bytes32(uint256(4567)));
        assertEq(registry.registeredAccounts(3), david);

        address[] memory addresses = registry.getRegisteredAccounts();
        assertEq(addresses.length, 4);
        assertEq(addresses[0], alice);
        assertEq(addresses[1], bob);
        assertEq(addresses[2], carol);
        assertEq(addresses[3], david);
    }

    function test_TheConstructorShouldRevertIfInvalidAddressList() public {
        // Fail
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.InvalidAddressList.selector));
        new EncryptionRegistry(Addresslist(address(this)));

        // OK
        (,, multisig,,,,,) = new DaoBuilder().withMultisigMember(alice).build();
    }

    /// @dev mock function for test_TheConstructorShouldRevertIfInvalidAddressList()
    function supportsInterface(bytes4) public pure returns (bool) {
        return false;
    }

    // Internal helpers

    function skipAppointedWallet(address appointedWallet) internal view returns (bool) {
        if (
            appointedWallet == address(0) || appointedWallet == alice || appointedWallet == bob
                || appointedWallet == carol || appointedWallet == david || Address.isContract(appointedWallet)
        ) return true;

        appointedWallet = address(uint160(appointedWallet) + 100);

        if (
            appointedWallet == address(0) || appointedWallet == alice || appointedWallet == bob
                || appointedWallet == carol || appointedWallet == david || Address.isContract(appointedWallet)
        ) return true;

        appointedWallet = address(uint160(appointedWallet) + 100);

        if (
            appointedWallet == address(0) || appointedWallet == alice || appointedWallet == bob
                || appointedWallet == carol || appointedWallet == david || Address.isContract(appointedWallet)
        ) return true;

        appointedWallet = address(uint160(appointedWallet) + 100);

        if (
            appointedWallet == address(0) || appointedWallet == alice || appointedWallet == bob
                || appointedWallet == carol || appointedWallet == david || Address.isContract(appointedWallet)
        ) return true;

        return false;
    }
}
