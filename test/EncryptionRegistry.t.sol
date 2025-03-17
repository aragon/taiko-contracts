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
import {
    SignerList,
    UPDATE_SIGNER_LIST_PERMISSION_ID,
    UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID
} from "../src/SignerList.sol";

contract EncryptionRegistryTest is AragonTest {
    EncryptionRegistry registry;
    DaoBuilder builder;
    DAO dao;
    Multisig multisig;

    // Events/errors to be tested here (duplicate)
    event PublicKeySet(address member, bytes32 publicKey);
    event AgentAppointed(address member, address appointedAgent);

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
        registry.appointAgent(address(0x1234000000000000000000000000000000000000));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));

        // Bob
        vm.startPrank(bob);
        registry.appointAgent(address(0x0000567800000000000000000000000000000000));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));

        // Carol
        vm.startPrank(carol);
        registry.appointAgent(address(0x0000000090aB0000000000000000000000000000));

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
        registry.appointAgent(address(0x000000000000cdEf000000000000000000000000));

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

    function testFuzz_ShouldRegisterMemberPublicKeys(address appointedAgent) public {
        if (skipAppointedWallet(appointedAgent)) return;

        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.appointAgent(appointedAgent);
        vm.startPrank(appointedAgent);
        registry.setPublicKey(alice, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.appointAgent(address(uint160(appointedAgent) + 10));
        vm.startPrank(address(uint160(appointedAgent) + 10));
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedAgent) + 10));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.appointAgent(address(uint160(appointedAgent) + 20));
        vm.startPrank(address(uint160(appointedAgent) + 20));
        registry.setPublicKey(carol, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedAgent) + 10));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(uint160(appointedAgent) + 20));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.appointAgent(address(uint160(appointedAgent) + 30));
        vm.startPrank(address(uint160(appointedAgent) + 30));
        registry.setPublicKey(david, 0x000000000000cdef000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedAgent) + 10));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(uint160(appointedAgent) + 20));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(david);
        assertEq(addrValue, address(uint160(appointedAgent) + 30));
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function testFuzz_ShouldClearPublicKeyAfterAppointing(address appointedAgent) public {
        if (skipAppointedWallet(appointedAgent)) return;

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

        registry.appointAgent(appointedAgent);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        registry.appointAgent(address(uint160(appointedAgent) + 10));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedAgent) + 10));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        registry.appointAgent(address(uint160(appointedAgent) + 20));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedAgent) + 10));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(uint160(appointedAgent) + 20));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(david);
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);

        registry.appointAgent(address(uint160(appointedAgent) + 30));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedAgent) + 10));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(carol);
        assertEq(addrValue, address(uint160(appointedAgent) + 20));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(david);
        assertEq(addrValue, address(uint160(appointedAgent) + 30));
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
        registry.appointAgent(address(0x1234));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1234));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // OK
        registry.appointAgent(address(0x1111));
        registry.appointAgent(address(0x2222));
        registry.appointAgent(address(0x3333));

        // KO
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.CannotAppointContracts.selector));
        registry.appointAgent(address(dao));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x3333));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // KO
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.CannotAppointContracts.selector));
        registry.appointAgent(address(multisig));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x3333));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // KO
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.CannotAppointContracts.selector));
        registry.appointAgent(address(registry));
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
        registry.appointAgent(address(0x0));

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Repeated appointments
        registry.appointAgent(address(0x1234));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1234));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointAgent(address(0x1234));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1234));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Bob
        registry.appointAgent(address(0x1111));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1111));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointAgent(address(0x1111));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1111));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointAgent(address(0x1111));
        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0x1111));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // More
        registry.appointAgent(address(0x2222));
        registry.appointAgent(address(0x2222));
        registry.appointAgent(address(0x2222));

        registry.appointAgent(address(0x3333));
        registry.appointAgent(address(0x3333));
        registry.appointAgent(address(0x3333));

        // OK again
        registry.appointAgent(address(0x1234));
        registry.appointAgent(address(0x1111));
        registry.appointAgent(address(0x2222));
        registry.appointAgent(address(0x3333));
    }

    function test_getRegisteredAccountsOnlyReturnsAddressesOnce() public {
        (address ad1,) = getWallet("wallet 1");
        (address ad2,) = getWallet("wallet 2");
        (address ad3,) = getWallet("wallet 3");

        assertEq(registry.getRegisteredAccounts().length, 0);

        vm.startPrank(alice);

        // No appointment
        registry.appointAgent(address(0x0));
        assertEq(registry.getRegisteredAccounts().length, 0, "Incorrect count");

        // Appoint + define pubKey's
        registry.appointAgent(ad1);
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        vm.startPrank(ad1);
        registry.setPublicKey(alice, hex"cdeef70d62f3a538739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        vm.startPrank(alice);
        registry.appointAgent(ad2);
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        vm.startPrank(ad2);
        registry.setPublicKey(alice, hex"00eef70d62f3a538739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        vm.startPrank(alice);
        registry.appointAgent(ad3);
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        vm.startPrank(ad3);
        registry.setPublicKey(alice, hex"0000f70d62f3a538739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        // Appoint self back
        vm.startPrank(alice);
        registry.appointAgent(address(0));
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        // Set own public key
        registry.setOwnPublicKey(hex"1deef70d62f3a538739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        // Appoint + define pubKey's (2)
        registry.appointAgent(ad1);
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        vm.startPrank(ad1);
        registry.setPublicKey(alice, hex"cdeef70d62f3a538739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        // Appoint self back
        vm.startPrank(alice);
        registry.appointAgent(address(0));
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        // BOB

        vm.startPrank(bob);

        // No appointment
        registry.appointAgent(address(0x0));
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect count");

        // Appoint + define pubKey's
        registry.appointAgent(ad1);
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");

        vm.startPrank(ad1);
        registry.setPublicKey(bob, hex"cdeef70d00000038739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");

        vm.startPrank(bob);
        registry.appointAgent(ad2);
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");

        vm.startPrank(ad2);
        registry.setPublicKey(bob, hex"00eef70d00000038739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");

        vm.startPrank(bob);
        registry.appointAgent(ad3);
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");

        vm.startPrank(ad3);
        registry.setPublicKey(bob, hex"0000f70d00000038739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");

        // Appoint self back
        vm.startPrank(bob);
        registry.appointAgent(address(0));
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");

        // Set own public key
        registry.setOwnPublicKey(hex"1deef70d00000038739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");

        // Appoint + define pubKey's (2)
        registry.appointAgent(ad1);
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");

        vm.startPrank(ad1);
        registry.setPublicKey(bob, hex"cdeef70d00000038739fb51629eeca7d7cd4852b26a5b469f16af187fdbc7152");
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect count");
    }

    function test_shouldRevertIfAppointingAnotherSigner() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointAgent(bob);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointAgent(carol);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointAgent(david);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointAgent(alice);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointAgent(carol);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyListed.selector));
        registry.appointAgent(david);

        // ok
        registry.appointAgent(address(0x5555));
    }

    function test_shouldRevertWhenAlreadyAppointed() public {
        vm.startPrank(alice);
        registry.appointAgent(address(0x1234));

        vm.startPrank(bob);
        registry.appointAgent(address(0x2345));

        // Fail
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyAppointed.selector));
        registry.appointAgent(address(0x2345));

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.AlreadyAppointed.selector));
        registry.appointAgent(address(0x1234));

        // ok
        registry.appointAgent(address(0x5555));
    }

    function testFuzz_AppointShouldRevertIfNotListed(address appointedAgent) public {
        if (Address.isContract(appointedAgent)) return;

        SignerList signerList;
        address addrValue;
        bytes32 bytesValue;

        // Only Alice
        (,, multisig,,, signerList, registry,) = new DaoBuilder().withMultisigMember(alice).build();
        if (signerList.isListed(appointedAgent)) return;

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
        registry.appointAgent(appointedAgent);
        vm.startPrank(appointedAgent);
        registry.setPublicKey(alice, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // NOT OK

        // Bob
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.appointAgent(address(uint160(appointedAgent) + 10));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.startPrank(address(uint160(appointedAgent) + 10));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setPublicKey(bob, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.appointAgent(address(uint160(appointedAgent) + 20));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.startPrank(address(uint160(appointedAgent) + 20));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setPublicKey(carol, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
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
        registry.appointAgent(address(uint160(appointedAgent) + 30));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        vm.startPrank(address(uint160(appointedAgent) + 30));
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeListed.selector));
        registry.setPublicKey(david, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
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

    function testFuzz_ShouldRevertOnSetPublicKeyIfNotAppointed(address appointedAgent) public {
        if (skipAppointedWallet(appointedAgent)) return;

        address addrValue;
        bytes32 bytesValue;

        // Alice
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeAppointed.selector));
        registry.setPublicKey(alice, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointAgent(appointedAgent);

        // Appointed
        vm.startPrank(appointedAgent);
        registry.setPublicKey(alice, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustBeAppointed.selector));
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        registry.appointAgent(address(uint160(appointedAgent) + 10));

        // Appointed
        vm.startPrank(address(uint160(appointedAgent) + 10));
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, address(uint160(appointedAgent) + 10));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
    }

    function testFuzz_ShouldRevertOnSetOwnPublicKeyIfOwnerIsAppointing(address appointedAgent) public {
        if (skipAppointedWallet(appointedAgent)) return;

        address addrValue;
        bytes32 bytesValue;

        // Alice
        vm.startPrank(alice);
        registry.appointAgent(appointedAgent);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustResetAppointedAgent.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Appointed
        registry.appointAgent(alice);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.appointAgent(appointedAgent);
        vm.expectRevert(abi.encodeWithSelector(IEncryptionRegistry.MustResetAppointedAgent.selector));
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.accounts(bob);
        assertEq(addrValue, appointedAgent);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Appointed
        registry.appointAgent(bob);
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
        registry.appointAgent(alice); // Self
        vm.expectEmit();
        emit PublicKeySet(alice, 0x0000000000000000cdef00000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x0000000000000000cdef00000000000000000000000000000000000000000000);

        vm.startPrank(bob);
        registry.appointAgent(bob); // Self
        vm.expectEmit();
        emit PublicKeySet(bob, 0x00000000000090ab000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x00000000000090ab000000000000000000000000000000000000000000000000);

        vm.startPrank(carol);
        registry.appointAgent(carol); // Self
        vm.expectEmit();
        emit PublicKeySet(carol, 0x0000000056780000000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x0000000056780000000000000000000000000000000000000000000000000000);

        vm.startPrank(david);
        registry.appointAgent(david); // Self
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
        registry.appointAgent(address(0x1234));
        assertEq(registry.getRegisteredAccounts().length, 1, "Incorrect length");

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect length");
        registry.appointAgent(address(0x5678));
        assertEq(registry.getRegisteredAccounts().length, 2, "Incorrect length");

        // Appoint first

        // Carol
        vm.startPrank(carol);
        registry.appointAgent(address(0x90ab));
        assertEq(registry.getRegisteredAccounts().length, 3, "Incorrect length");
        registry.appointAgent(address(0x6666));
        vm.startPrank(address(0x6666));
        registry.setPublicKey(carol, bytes32(uint256(3456)));
        assertEq(registry.getRegisteredAccounts().length, 3, "Incorrect length");

        // David
        vm.startPrank(david);
        registry.appointAgent(address(0xcdef));
        assertEq(registry.getRegisteredAccounts().length, 4, "Incorrect length");
        registry.appointAgent(address(0x7777));
        vm.startPrank(address(0x7777));
        registry.setPublicKey(david, bytes32(uint256(4567)));
        assertEq(registry.getRegisteredAccounts().length, 4, "Incorrect length");
    }

    function test_ShouldEnumerateRegisteredAddresses() public {
        // Set public key first

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        assertEq(registry.accountList(0), alice);
        registry.appointAgent(address(0x1234));
        assertEq(registry.accountList(0), alice);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.accountList(1), bob);
        registry.appointAgent(address(0x5678));
        assertEq(registry.accountList(1), bob);

        // Appoint first

        // Carol
        vm.startPrank(carol);
        registry.appointAgent(address(0x90ab));
        assertEq(registry.accountList(2), carol);
        registry.appointAgent(address(0x6666));
        vm.startPrank(address(0x6666));
        registry.setPublicKey(carol, bytes32(uint256(3456)));
        assertEq(registry.accountList(2), carol);

        // David
        vm.startPrank(david);
        registry.appointAgent(address(0xcdef));
        assertEq(registry.accountList(3), david);
        registry.appointAgent(address(0x7777));
        vm.startPrank(address(0x7777));
        registry.setPublicKey(david, bytes32(uint256(4567)));
        assertEq(registry.accountList(3), david);

        assertEq(registry.getRegisteredAccounts().length, 4, "Incorrect length");

        assertEq(registry.accountList(0), alice);
        assertEq(registry.accountList(1), bob);
        assertEq(registry.accountList(2), carol);
        assertEq(registry.accountList(3), david);
    }

    function test_ShouldLoadTheRegisteredAddresses() public {
        // Set public key first

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        assertEq(registry.accountList(0), alice);
        registry.appointAgent(address(0x1234));
        assertEq(registry.accountList(0), alice);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.accountList(1), bob);
        registry.appointAgent(address(0x5678));
        assertEq(registry.accountList(1), bob);

        // Appoint first

        // Carol
        vm.startPrank(carol);
        registry.appointAgent(address(0x90ab));
        assertEq(registry.accountList(2), carol);
        registry.appointAgent(address(0x6666));
        vm.startPrank(address(0x6666));
        registry.setPublicKey(carol, bytes32(uint256(3456)));
        assertEq(registry.accountList(2), carol);

        // David
        vm.startPrank(david);
        registry.appointAgent(address(0xcdef));
        assertEq(registry.accountList(3), david);
        registry.appointAgent(address(0x7777));
        vm.startPrank(address(0x7777));
        registry.setPublicKey(david, bytes32(uint256(4567)));
        assertEq(registry.accountList(3), david);

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

    function test_ShouldRemoveUnusedAddresses() public {
        SignerList signerList;
        (dao,,,,, signerList, registry,) = new DaoBuilder().withMultisigMember(alice).withMultisigMember(bob).withMultisigMember(
            carol
        ).withMultisigMember(david).build();

        vm.startPrank(alice);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        // All are a signer
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1)));
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2)));
        vm.startPrank(carol);
        registry.setOwnPublicKey(bytes32(uint256(3)));
        vm.startPrank(david);
        registry.setOwnPublicKey(bytes32(uint256(4)));

        // Add more
        address[] memory _signers = new address[](2);
        _signers[0] = address(0x1234);
        _signers[1] = address(0x2345);
        vm.startPrank(alice);
        signerList.addSigners(_signers);

        // New signers
        vm.startPrank(address(0x1234));
        registry.setOwnPublicKey(bytes32(uint256(5)));
        vm.startPrank(address(0x2345));
        registry.setOwnPublicKey(bytes32(uint256(6)));

        vm.assertEq(registry.accountList(0), alice);                                                                                                                                                                                                    
        vm.assertEq(registry.accountList(1), bob);
        vm.assertEq(registry.accountList(2), carol);
        vm.assertEq(registry.accountList(3), david);
        vm.assertEq(registry.accountList(4), address(0x1234));
        vm.assertEq(registry.accountList(5), address(0x2345));

        // Clean
        vm.startPrank(alice);
        signerList.removeSigners(_signers);
        registry.removeUnused();

        vm.assertEq(registry.accountList(0), alice);
        vm.assertEq(registry.accountList(1), bob);
        vm.assertEq(registry.accountList(2), carol);
        vm.assertEq(registry.accountList(3), david);
        vm.expectRevert();
        vm.assertEq(registry.accountList(4), address(0));
        vm.expectRevert();
        vm.assertEq(registry.accountList(5), address(0));
    }

    /// @dev mock function for test_TheConstructorShouldRevertIfInvalidAddressList()
    function supportsInterface(bytes4) public pure returns (bool) {
        return false;
    }

    // Internal helpers

    function skipAppointedWallet(address appointedAgent) internal view returns (bool) {
        // Avoid fuzz tests overflowing
        if (appointedAgent >= address(uint160(0xFFFfFFfFfFFffFFfFFFffffFfFfFffFFfFFFFF00))) return true;

        if (
            appointedAgent == address(0) || appointedAgent == alice || appointedAgent == bob || appointedAgent == carol
                || appointedAgent == david || Address.isContract(appointedAgent)
        ) return true;

        appointedAgent = address(uint160(appointedAgent) + 10);

        if (
            appointedAgent == address(0) || appointedAgent == alice || appointedAgent == bob || appointedAgent == carol
                || appointedAgent == david || Address.isContract(appointedAgent)
        ) return true;

        appointedAgent = address(uint160(appointedAgent) + 10);

        if (
            appointedAgent == address(0) || appointedAgent == alice || appointedAgent == bob || appointedAgent == carol
                || appointedAgent == david || Address.isContract(appointedAgent)
        ) return true;

        appointedAgent = address(uint160(appointedAgent) + 10);

        if (
            appointedAgent == address(0) || appointedAgent == alice || appointedAgent == bob || appointedAgent == carol
                || appointedAgent == david || Address.isContract(appointedAgent)
        ) return true;

        return false;
    }
}
