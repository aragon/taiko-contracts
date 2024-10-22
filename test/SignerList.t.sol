// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {EncryptionRegistry} from "../src/EncryptionRegistry.sol";
import {SignerList} from "../src/SignerList.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../src/Multisig.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract EncryptionRegistryTest is AragonTest {
    SignerList signerList;
    EncryptionRegistry encryptionRegistry;
    DaoBuilder builder;
    DAO dao;
    Multisig multisig;
    address[] signers;

    // Events/errors to be tested here (duplicate)
    error SignerListLengthOutOfBounds(uint16 limit, uint256 actual);
    error InvalidEncryptionRegitry(address givenAddress);

    function setUp() public {
        builder = new DaoBuilder();
        (dao,, multisig,,, signerList, encryptionRegistry,) = builder.withMultisigMember(alice).withMultisigMember(bob)
            .withMultisigMember(carol).withMultisigMember(david).build();

        signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;
    }

    // Initialize
    function test_InitializeRevertsIfInitialized() public {
        signerList = new SignerList();
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(address(0)), 0));

        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(address(0)), 0));
    }

    function test_InitializeSetsTheRightValues() public {
        // 1
        signerList = new SignerList();
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(address(0)), 0));

        (EncryptionRegistry reg, uint16 minSignerListLength) = signerList.settings();
        vm.assertEq(address(reg), address(0), "Incorrect address");
        vm.assertEq(minSignerListLength, 0);
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");

        // 2
        signerList = new SignerList();
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(encryptionRegistry), 0));

        (reg, minSignerListLength) = signerList.settings();
        vm.assertEq(address(reg), address(encryptionRegistry), "Incorrect address");
        vm.assertEq(minSignerListLength, 0);
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");

        // 3
        signerList = new SignerList();
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(encryptionRegistry), 2));

        (reg, minSignerListLength) = signerList.settings();
        vm.assertEq(address(reg), address(encryptionRegistry), "Incorrect address");
        vm.assertEq(minSignerListLength, 2);
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(100)), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(200)), false, "Should not be a signer");

        // 4
        signers = new address[](2);
        signers[0] = address(100);
        signers[0] = address(200);
        signerList = new SignerList();
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(encryptionRegistry), 1));

        (reg, minSignerListLength) = signerList.settings();
        vm.assertEq(address(reg), address(encryptionRegistry), "Incorrect address");
        vm.assertEq(minSignerListLength, 1);
        vm.assertEq(signerList.addresslistLength(), 2, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(bob), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(carol), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(david), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(100)), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(200)), true, "Should be a signer");
    }

    function test_InitializingWithAnInvalidRegistryShouldRevert() public {
        // 1
        signerList = new SignerList();
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(address(alice)), 2));

        vm.expectRevert(InvalidEncryptionRegitry.selector);

        // 2
        signerList = new SignerList();
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(address(bob)), 3));

        vm.expectRevert(InvalidEncryptionRegitry.selector);

        // OK
        signerList = new SignerList();
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(encryptionRegistry), 2));
    }

    function test_InitializingWithTooManySignersReverts() public {
        // 1
        signers = new address[](type(uint16).max + 1);

        signerList = new SignerList();
        vm.expectRevert(
            abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, type(uint16).max, type(uint16).max + 1)
        );
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(address(0)), 0));

        // 2
        signers = new address[](type(uint16).max + 10);

        signerList = new SignerList();
        vm.expectRevert(
            abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, type(uint16).max, type(uint16).max + 10)
        );
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(address(0)), 0));
    }
}
