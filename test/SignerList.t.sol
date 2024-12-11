// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {EncryptionRegistry} from "../src/EncryptionRegistry.sol";
import {
    SignerList,
    ISignerList,
    UPDATE_SIGNER_LIST_PERMISSION_ID,
    UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID
} from "../src/SignerList.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../src/Multisig.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {createProxyAndCall} from "../src/helpers/proxy.sol";

contract SignerListTest is AragonTest {
    SignerList signerList;
    EncryptionRegistry encryptionRegistry;
    DaoBuilder builder;
    DAO dao;
    Multisig multisig;
    address[] signers;

    address immutable SIGNER_LIST_BASE = address(new SignerList());

    // Events/errors to be tested here (duplicate)
    error SignerListLengthOutOfBounds(uint16 limit, uint256 actual);
    error InvalidEncryptionRegitry(address givenAddress);
    error DaoUnauthorized(address dao, address where, address who, bytes32 permissionId);
    error InvalidAddresslistUpdate(address member);

    event SignerListSettingsUpdated(EncryptionRegistry encryptionRegistry, uint16 minSignerListLength);
    event SignersAdded(address[] signers);
    event SignersRemoved(address[] signers);

    function setUp() public {
        vm.startPrank(alice);

        builder = new DaoBuilder();
        (dao,, multisig,,, signerList, encryptionRegistry,) = builder.withMultisigMember(alice).withMultisigMember(bob)
            .withMultisigMember(carol).withMultisigMember(david).build();

        vm.roll(block.number + 1);

        signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;
    }

    function test_WhenDeployingTheContract() external {
        // It should disable the initializers
        signerList = new SignerList();

        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        signerList.initialize(dao, signers);
    }

    function test_WhenCloningTheContract() external {
        // It should initialize normally
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );
    }

    function test_GivenADeployedContract() external {
        // It should refuse to initialize again
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );

        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        signerList.initialize(dao, signers);
    }

    modifier givenANewInstance() {
        _;
    }

    modifier givenCallingInitialize() {
        _;
    }

    function test_GivenCallingInitialize() external givenANewInstance givenCallingInitialize {
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );

        // It should set the DAO address
        vm.assertEq(address(signerList.dao()), address(dao), "Incorrect DAO addres");

        (EncryptionRegistry reg, uint16 minSignerListLength) = signerList.settings();

        // It should append the new addresses to the list
        // It should return true on isListed
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(100)), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(200)), false, "Should not be a signer");

        // It the encryption registry should be empty
        vm.assertEq(address(reg), address(0), "Incorrect address");

        // It minSignerListLength should be zero
        vm.assertEq(minSignerListLength, 0);

        // It should emit the SignersAdded event
        vm.expectEmit();
        emit SignersAdded({signers: signers});
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );

        // It should set the right values in general

        // 2
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );

        (reg, minSignerListLength) = signerList.settings();
        vm.assertEq(address(reg), address(0), "Incorrect address");
        vm.assertEq(minSignerListLength, 0);
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(100)), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(200)), false, "Should not be a signer");

        // 3
        signers = new address[](2);
        signers[0] = address(100);
        signers[1] = address(200);

        // It should emit the SignersAdded event
        vm.expectEmit();
        emit SignersAdded({signers: signers});
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );

        (reg, minSignerListLength) = signerList.settings();
        vm.assertEq(address(reg), address(0), "Incorrect address");
        vm.assertEq(minSignerListLength, 0);
        vm.assertEq(signerList.addresslistLength(), 2, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(bob), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(carol), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(david), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(100)), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(200)), true, "Should be a signer");
    }

    function test_RevertGiven_PassingMoreAddressesThanSupportedOnInitialize()
        external
        givenANewInstance
        givenCallingInitialize
    {
        // It should revert

        // 1
        signers = new address[](uint256(type(uint16).max) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SignerListLengthOutOfBounds.selector, type(uint16).max, uint256(type(uint16).max) + 1
            )
        );
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );

        // 2
        signers = new address[](uint256(type(uint16).max) + 10);
        vm.expectRevert(
            abi.encodeWithSelector(
                SignerListLengthOutOfBounds.selector, type(uint16).max, uint256(type(uint16).max) + 10
            )
        );
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );
    }

    function test_RevertGiven_DuplicateAddressesOnInitialize() external givenANewInstance givenCallingInitialize {
        // It should revert

        // 1
        signers[2] = signers[1];

        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, signers[2]));
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );
    }

    modifier whenCallingUpdateSettings() {
        // Initialize
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );

        // Grant update permission to Alice
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        _;
    }

    function test_WhenCallingUpdateSettings() external whenCallingUpdateSettings {
        encryptionRegistry = new EncryptionRegistry(signerList);

        // 1
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 0));

        (EncryptionRegistry reg, uint16 minSignerListLength) = signerList.settings();

        // It sets the new encryption registry
        vm.assertEq(address(reg), address(encryptionRegistry), "Incorrect encryptionRegistry");

        // It sets the new minSignerListLength
        vm.assertEq(minSignerListLength, 0);

        // It should emit a SignerListSettingsUpdated event
        vm.expectEmit();
        emit SignerListSettingsUpdated({encryptionRegistry: encryptionRegistry, minSignerListLength: 0});
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 0));

        // 2
        encryptionRegistry = new EncryptionRegistry(signerList);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 3));

        (reg, minSignerListLength) = signerList.settings();

        // It sets the new encryption registry
        vm.assertEq(address(reg), address(encryptionRegistry), "Incorrect encryptionRegistry");

        // It sets the new minSignerListLength
        vm.assertEq(minSignerListLength, 3);

        // It should emit a SignerListSettingsUpdated event
        vm.expectEmit();
        emit SignerListSettingsUpdated({encryptionRegistry: encryptionRegistry, minSignerListLength: 4});
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 4));
    }

    function test_RevertWhen_UpdateSettingsWithoutThePermission() external whenCallingUpdateSettings {
        // It should revert

        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(signerList),
                bob,
                UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID
            )
        );
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 0));
    }

    function test_RevertWhen_EncryptionRegistryIsNotCompatible() external whenCallingUpdateSettings {
        // It should revert

        vm.expectRevert(abi.encodeWithSelector(InvalidEncryptionRegitry.selector, address(dao)));
        signerList.updateSettings(SignerList.Settings(EncryptionRegistry(address(dao)), 0));

        vm.expectRevert();
        signerList.updateSettings(SignerList.Settings(EncryptionRegistry(bob), 0));
    }

    function test_RevertWhen_MinSignerListLengthIsBiggerThanTheListSize() external whenCallingUpdateSettings {
        // It should revert

        // 1
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 4, 15));
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 15));

        // 2
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 4, 20));
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 20));

        // 3
        signers = new address[](1);
        signerList.addSigners(signers);
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 5, 50));
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 50));
    }

    function test_WhenCallingSupportsInterface() external view {
        // It does not support the empty interface
        bool supported = signerList.supportsInterface(bytes4(0xffffffff));
        assertEq(supported, false, "Should not support the empty interface");

        // It supports IERC165Upgradeable
        supported = signerList.supportsInterface(type(IERC165Upgradeable).interfaceId);
        assertEq(supported, true, "Should support IERC165Upgradeable");

        // It supports Addresslist
        supported = signerList.supportsInterface(type(Addresslist).interfaceId);
        assertEq(supported, true, "Should support Addresslist");

        // It supports ISignerList
        supported = signerList.supportsInterface(type(ISignerList).interfaceId);
        assertEq(supported, true, "Should support ISignerList");
    }

    modifier whenCallingAddSigners() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        _;
    }

    function test_WhenCallingAddSigners() external whenCallingAddSigners {
        // It should append the new addresses to the list
        // It should return true on isListed

        // 0
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(100)), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(200)), false, "Should not be a signer");

        // 1
        address[] memory newSigners = new address[](1);
        newSigners[0] = address(100);
        signerList.addSigners(newSigners);

        vm.assertEq(signerList.addresslistLength(), 5, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(100)), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(200)), false, "Should not be a signer");

        // 2
        newSigners[0] = address(200);
        signerList.addSigners(newSigners);

        vm.assertEq(signerList.addresslistLength(), 6, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(100)), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(200)), true, "Should be a signer");

        // It should emit the SignersAdded event
        newSigners[0] = address(300);
        vm.expectEmit();
        emit SignersAdded({signers: newSigners});
        signerList.addSigners(newSigners);
    }

    function test_RevertWhen_AddingWithoutThePermission() external whenCallingAddSigners {
        dao.revoke(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        // It should revert

        address[] memory newSigners = new address[](1);
        newSigners[0] = address(100);

        // 1
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID
            )
        );
        signerList.addSigners(newSigners);

        // 2
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(signerList), bob, UPDATE_SIGNER_LIST_PERMISSION_ID
            )
        );
        signerList.addSigners(newSigners);
    }

    function test_RevertGiven_PassingMoreAddressesThanSupportedOnAddSigners() external whenCallingAddSigners {
        // It should revert

        uint256 addedSize = uint256(type(uint16).max);

        // 1
        address[] memory newSigners = new address[](addedSize);
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, type(uint16).max, addedSize + 4));
        signerList.addSigners(newSigners);

        // 2
        addedSize = uint256(type(uint16).max) + 10;
        newSigners = new address[](addedSize);
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, type(uint16).max, addedSize + 4));
        signerList.addSigners(newSigners);
    }

    function test_RevertGiven_DuplicateAddressesOnAddSigners() external whenCallingAddSigners {
        // It should revert

        // 1
        address[] memory newSigners = new address[](1);
        newSigners[0] = alice; // Alice is a signer already
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, newSigners[0]));
        signerList.addSigners(newSigners);

        // 2
        newSigners[0] = bob; // Bob is a signer already
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, newSigners[0]));
        signerList.addSigners(newSigners);

        // OK
        newSigners[0] = address(1234);
        signerList.addSigners(newSigners);
    }

    modifier whenCallingRemoveSigners() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        _;
    }

    function test_WhenCallingRemoveSigners() external whenCallingRemoveSigners {
        // It should remove the given addresses
        // It should return false on isListed

        address[] memory newSigners = new address[](3);
        newSigners[0] = address(100);
        newSigners[1] = address(200);
        newSigners[2] = address(300);
        signerList.addSigners(newSigners);

        // 0
        vm.assertEq(signerList.addresslistLength(), 7, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(100)), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(200)), true, "Should be a signer");

        // 1
        address[] memory rmSigners = new address[](1);
        rmSigners[0] = david;
        signerList.removeSigners(rmSigners);

        vm.assertEq(signerList.addresslistLength(), 6, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(100)), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(200)), true, "Should be a signer");

        // 2
        rmSigners[0] = carol;
        signerList.removeSigners(rmSigners);

        vm.assertEq(signerList.addresslistLength(), 5, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(david), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(100)), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(200)), true, "Should be a signer");

        // It should emit the SignersRemoved event
        rmSigners[0] = bob;
        vm.expectEmit();
        emit SignersRemoved({signers: rmSigners});
        signerList.removeSigners(rmSigners);
    }

    function test_RevertWhen_RemovingWithoutThePermission() external whenCallingRemoveSigners {
        address[] memory newSigners = new address[](3);
        newSigners[0] = address(100);
        newSigners[1] = address(200);
        newSigners[2] = address(300);
        signerList.addSigners(newSigners);

        dao.revoke(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        address[] memory rmSigners = new address[](2);
        rmSigners[0] = david;

        // It should revert

        // 1
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID
            )
        );
        signerList.removeSigners(newSigners);

        // 2
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(signerList), bob, UPDATE_SIGNER_LIST_PERMISSION_ID
            )
        );
        signerList.removeSigners(newSigners);
    }

    function test_RevertWhen_RemovingAnUnlistedAddress() external whenCallingRemoveSigners {
        address[] memory newSigners = new address[](1);
        newSigners[0] = address(100);
        signerList.addSigners(newSigners);

        // It should revert

        // 1
        address[] memory rmSigners = new address[](1);
        rmSigners[0] = address(200);
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, rmSigners[0]));
        signerList.removeSigners(rmSigners);

        // 2
        rmSigners[0] = address(500);
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, rmSigners[0]));
        signerList.removeSigners(rmSigners);
    }

    function test_RevertGiven_RemovingTooManyAddresses() external whenCallingRemoveSigners {
        address[] memory newSigners = new address[](1);
        newSigners[0] = address(100);
        signerList.addSigners(newSigners);

        // It should revert
        // NOTE: The new list will be smaller than minSignerListLength

        // 1
        address[] memory rmSigners = new address[](2);
        rmSigners[0] = david;
        rmSigners[1] = carol;
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 4, 3));
        signerList.removeSigners(rmSigners);

        // 2
        rmSigners = new address[](3);
        rmSigners[0] = david;
        rmSigners[1] = carol;
        rmSigners[2] = bob;
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 4, 2));
        signerList.removeSigners(rmSigners);

        // OK
        rmSigners = new address[](1);
        rmSigners[0] = david;
        signerList.removeSigners(rmSigners);
    }

    modifier whenCallingIsListed() {
        signerList = SignerList(
            createProxyAndCall(address(SIGNER_LIST_BASE), abi.encodeCall(SignerList.initialize, (dao, signers)))
        );

        _;
    }

    function test_GivenTheMemberIsListed() external whenCallingIsListed {
        // It returns true

        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
    }

    function test_GivenTheMemberIsNotListed() external whenCallingIsListed {
        // It returns false

        vm.assertEq(signerList.isListed(address(100)), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(200)), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(400)), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(800)), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(1234)), false, "Should not be a signer");
    }

    function testFuzz_GivenTheMemberIsNotListed(address random) external whenCallingIsListed {
        if (random == alice || random == bob || random == carol || random == david) return;

        // It returns false

        vm.assertEq(signerList.isListed(random), false, "Should not be a signer");
    }

    modifier whenCallingIsListedAtBlock() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        _;
    }

    modifier givenTheMemberWasListed() {
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");

        _;
    }

    function test_GivenTheMemberIsNotListedNow() external whenCallingIsListedAtBlock givenTheMemberWasListed {
        vm.roll(block.number + 1);

        // Replace the list
        address[] memory newSigners = new address[](4);
        newSigners[0] = address(0);
        newSigners[1] = address(1);
        newSigners[2] = address(2);
        newSigners[3] = address(3);
        signerList.addSigners(newSigners);
        address[] memory rmSigners = new address[](4);
        rmSigners[0] = alice;
        rmSigners[1] = bob;
        rmSigners[2] = carol;
        rmSigners[3] = david;
        signerList.removeSigners(rmSigners);

        // It returns true
        vm.assertEq(signerList.isListedAtBlock(alice, block.number - 1), true, "Should be a signer");
        vm.assertEq(signerList.isListedAtBlock(bob, block.number - 1), true, "Should be a signer");
        vm.assertEq(signerList.isListedAtBlock(carol, block.number - 1), true, "Should be a signer");
        vm.assertEq(signerList.isListedAtBlock(david, block.number - 1), true, "Should be a signer");
    }

    function test_GivenTheMemberIsListedNow() external whenCallingIsListedAtBlock givenTheMemberWasListed {
        vm.roll(block.number + 1);

        // It returns true
        vm.assertEq(signerList.isListedAtBlock(alice, block.number - 1), true, "Should be a signer");
        vm.assertEq(signerList.isListedAtBlock(bob, block.number - 1), true, "Should be a signer");
        vm.assertEq(signerList.isListedAtBlock(carol, block.number - 1), true, "Should be a signer");
        vm.assertEq(signerList.isListedAtBlock(david, block.number - 1), true, "Should be a signer");
    }

    modifier givenTheMemberWasNotListed() {
        // Replace the list
        address[] memory newSigners = new address[](4);
        newSigners[0] = address(0);
        newSigners[1] = address(1);
        newSigners[2] = address(2);
        newSigners[3] = address(3);
        signerList.addSigners(newSigners);
        address[] memory rmSigners = new address[](4);
        rmSigners[0] = alice;
        rmSigners[1] = bob;
        rmSigners[2] = carol;
        rmSigners[3] = david;
        signerList.removeSigners(rmSigners);

        // +1
        vm.roll(block.number + 1);

        _;
    }

    function test_GivenTheMemberIsDelistedNow() external whenCallingIsListedAtBlock givenTheMemberWasNotListed {
        // It returns false
        vm.assertEq(signerList.isListedAtBlock(alice, block.number - 1), false, "Should not be a signer");
        vm.assertEq(signerList.isListedAtBlock(bob, block.number - 1), false, "Should not be a signer");
        vm.assertEq(signerList.isListedAtBlock(carol, block.number - 1), false, "Should not be a signer");
        vm.assertEq(signerList.isListedAtBlock(david, block.number - 1), false, "Should not be a signer");
    }

    function test_GivenTheMemberIsEnlistedNow() external whenCallingIsListedAtBlock givenTheMemberWasNotListed {
        // Add again
        address[] memory newSigners = new address[](4);
        newSigners[0] = alice;
        newSigners[1] = bob;
        newSigners[2] = carol;
        newSigners[3] = david;
        signerList.addSigners(newSigners);

        // It returns false
        vm.assertEq(signerList.isListedAtBlock(alice, block.number - 1), false, "Should not be a signer");
        vm.assertEq(signerList.isListedAtBlock(bob, block.number - 1), false, "Should not be a signer");
        vm.assertEq(signerList.isListedAtBlock(carol, block.number - 1), false, "Should not be a signer");
        vm.assertEq(signerList.isListedAtBlock(david, block.number - 1), false, "Should not be a signer");
    }

    modifier whenCallingIsListedOrAppointedByListed() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 2));

        // Remove Carol and David
        address[] memory rmSigners = new address[](2);
        rmSigners[0] = carol;
        rmSigners[1] = david;
        signerList.removeSigners(rmSigners);

        // Alice (owner) appoints david
        encryptionRegistry.appointAgent(david);

        // Bob is the owner

        _;
    }

    function test_GivenTheCallerIsAListedSigner() external whenCallingIsListedOrAppointedByListed {
        // 1
        bool listedOrAppointedByListed = signerList.isListedOrAppointedByListed(alice);

        // It listedOrAppointedByListed should be true
        assertEq(listedOrAppointedByListed, true, "listedOrAppointedByListed should be true");

        // 2
        listedOrAppointedByListed = signerList.isListedOrAppointedByListed(bob);

        // It listedOrAppointedByListed should be true
        assertEq(listedOrAppointedByListed, true, "listedOrAppointedByListed should be true");
    }

    function test_GivenTheCallerIsAppointedByASigner() external whenCallingIsListedOrAppointedByListed {
        bool listedOrAppointedByListed = signerList.isListedOrAppointedByListed(david);

        // It listedOrAppointedByListed should be true
        assertEq(listedOrAppointedByListed, true, "listedOrAppointedByListed should be true");
    }

    function test_GivenTheCallerIsNotListedOrAppointed() external whenCallingIsListedOrAppointedByListed {
        // 1
        bool listedOrAppointedByListed = signerList.isListedOrAppointedByListed(carol);

        // It listedOrAppointedByListed should be false
        assertEq(listedOrAppointedByListed, false, "listedOrAppointedByListed should be false");

        // 2
        listedOrAppointedByListed = signerList.isListedOrAppointedByListed(address(1234));

        // It listedOrAppointedByListed should be false
        assertEq(listedOrAppointedByListed, false, "listedOrAppointedByListed should be false");
    }

    modifier whenCallingGetListedEncryptionOwnerAtBlock() {
        // Alice (owner) appoints address(0x1234)
        encryptionRegistry.appointAgent(address(0x1234));

        // Bob (owner) appoints address(0x2345)
        vm.startPrank(bob);
        encryptionRegistry.appointAgent(address(0x2345));

        vm.startPrank(alice);

        // Carol is owner
        // David is owner

        _;
    }

    modifier givenTheResolvedOwnerIsListedOnGetListedEncryptionOwnerAtBlock() {
        _;
    }

    function test_WhenTheGivenAddressIsTheOwner()
        external
        whenCallingGetListedEncryptionOwnerAtBlock
        givenTheResolvedOwnerIsListedOnGetListedEncryptionOwnerAtBlock
    {
        address resolvedOwner;

        // It should return the given address
        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(alice, block.number - 1);
        assertEq(resolvedOwner, alice, "Should be alice");

        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(bob, block.number - 1);
        assertEq(resolvedOwner, bob, "Should be bob");

        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(carol, block.number - 1);
        assertEq(resolvedOwner, carol, "Should be carol");

        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(david, block.number - 1);
        assertEq(resolvedOwner, david, "Should be david");
    }

    function test_WhenTheGivenAddressIsAppointedByTheOwner()
        external
        whenCallingGetListedEncryptionOwnerAtBlock
        givenTheResolvedOwnerIsListedOnGetListedEncryptionOwnerAtBlock
    {
        address resolvedOwner;

        // It should return the resolved owner
        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(address(0x1234), block.number - 1);
        assertEq(resolvedOwner, alice, "Should be alice");

        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(address(0x2345), block.number - 1);
        assertEq(resolvedOwner, bob, "Should be bob");
    }

    modifier givenTheResolvedOwnerWasListedOnGetListedEncryptionOwnerAtBlock() {
        // But not listed now
        // Prior appointments are still in place

        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        address[] memory mvSigners = new address[](4);
        mvSigners[0] = address(0x5555);
        mvSigners[1] = address(0x6666);
        mvSigners[2] = address(0x7777);
        mvSigners[3] = address(0x8888);
        signerList.addSigners(mvSigners);

        vm.roll(block.number + 1);

        mvSigners[0] = alice;
        mvSigners[1] = bob;
        mvSigners[2] = carol;
        mvSigners[3] = david;
        signerList.removeSigners(mvSigners);

        _;
    }

    function test_WhenTheGivenAddressIsTheOwner2()
        external
        whenCallingGetListedEncryptionOwnerAtBlock
        givenTheResolvedOwnerWasListedOnGetListedEncryptionOwnerAtBlock
    {
        address resolvedOwner;

        // It should return the given address
        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(alice, block.number - 1);
        assertEq(resolvedOwner, alice, "Should be alice");

        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(bob, block.number - 1);
        assertEq(resolvedOwner, bob, "Should be bob");

        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(carol, block.number - 1);
        assertEq(resolvedOwner, carol, "Should be carol");

        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(david, block.number - 1);
        assertEq(resolvedOwner, david, "Should be david");
    }

    function test_WhenTheGivenAddressIsAppointedByTheOwner2()
        external
        whenCallingGetListedEncryptionOwnerAtBlock
        givenTheResolvedOwnerWasListedOnGetListedEncryptionOwnerAtBlock
    {
        address resolvedOwner;

        // It should return the resolved owner
        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(address(0x1234), block.number - 1);
        assertEq(resolvedOwner, alice, "Should be alice");

        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(address(0x2345), block.number - 1);
        assertEq(resolvedOwner, bob, "Should be bob");
    }

    function test_GivenTheResolvedOwnerWasNotListedOnGetListedEncryptionOwnerAtBlock()
        external
        whenCallingGetListedEncryptionOwnerAtBlock
    {
        address resolvedOwner;

        // It should return a zero value
        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(address(0x3456), block.number - 1);
        assertEq(resolvedOwner, address(0), "Should be zero");

        resolvedOwner = signerList.getListedEncryptionOwnerAtBlock(address(0x4567), block.number - 1);
        assertEq(resolvedOwner, address(0), "Should be zero");
    }

    modifier whenCallingResolveEncryptionAccountAtBlock() {
        // Alice (owner) appoints address(0x1234)
        encryptionRegistry.appointAgent(address(0x1234));

        // Bob (owner) appoints address(0x2345)
        vm.startPrank(bob);
        encryptionRegistry.appointAgent(address(0x2345));

        vm.startPrank(alice);

        // Carol is owner
        // David is owner

        _;
    }

    modifier givenTheResolvedOwnerIsListedOnResolveEncryptionAccountAtBlock() {
        _;
    }

    function test_WhenTheGivenAddressIsOwner()
        external
        whenCallingResolveEncryptionAccountAtBlock
        givenTheResolvedOwnerIsListedOnResolveEncryptionAccountAtBlock
    {
        address resolvedOwner;
        address votingWallet;

        // 1 - owner appoints

        // It owner should be the given address
        // It votingWallet should be the resolved appointed wallet
        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(alice, block.number - 1);
        assertEq(resolvedOwner, alice, "Should be alice");
        assertEq(votingWallet, address(0x1234), "Should be 0x1234");

        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(bob, block.number - 1);
        assertEq(resolvedOwner, bob, "Should be bob");
        assertEq(votingWallet, address(0x2345), "Should be 0x2345");

        // 2 - No appointed wallet

        // It owner should be the given address
        // It votingWallet should be the resolved appointed wallet
        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(carol, block.number - 1);
        assertEq(resolvedOwner, carol, "Should be carol");
        assertEq(votingWallet, carol, "Should be carol");

        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(david, block.number - 1);
        assertEq(resolvedOwner, david, "Should be david");
        assertEq(votingWallet, david, "Should be david");
    }

    function test_WhenTheGivenAddressIsAppointed()
        external
        whenCallingResolveEncryptionAccountAtBlock
        givenTheResolvedOwnerIsListedOnResolveEncryptionAccountAtBlock
    {
        address resolvedOwner;
        address votingWallet;

        // It owner should be the resolved owner
        // It votingWallet should be the given address
        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(address(0x1234), block.number - 1);
        assertEq(resolvedOwner, alice, "Should be alice");
        assertEq(votingWallet, address(0x1234), "Should be 0x1234");

        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(address(0x2345), block.number - 1);
        assertEq(resolvedOwner, bob, "Should be bob");
        assertEq(votingWallet, address(0x2345), "Should be 0x2345");
    }

    modifier givenTheResolvedOwnerWasListedOnResolveEncryptionAccountAtBlock() {
        // But not listed now
        // Prior appointments are still in place

        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        address[] memory mvSigners = new address[](4);
        mvSigners[0] = address(0x5555);
        mvSigners[1] = address(0x6666);
        mvSigners[2] = address(0x7777);
        mvSigners[3] = address(0x8888);
        signerList.addSigners(mvSigners);

        vm.roll(block.number + 1);

        mvSigners[0] = alice;
        mvSigners[1] = bob;
        mvSigners[2] = carol;
        mvSigners[3] = david;
        signerList.removeSigners(mvSigners);

        _;
    }

    function test_WhenTheGivenAddressIsOwner2()
        external
        whenCallingResolveEncryptionAccountAtBlock
        givenTheResolvedOwnerWasListedOnResolveEncryptionAccountAtBlock
    {
        address resolvedOwner;
        address votingWallet;

        // 1 - owner appoints

        // It owner should be the given address
        // It votingWallet should be the resolved appointed wallet
        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(alice, block.number - 1);
        assertEq(resolvedOwner, alice, "Should be alice");
        assertEq(votingWallet, address(0x1234), "Should be 0x1234");

        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(bob, block.number - 1);
        assertEq(resolvedOwner, bob, "Should be bob");
        assertEq(votingWallet, address(0x2345), "Should be 0x2345");

        // 2 - No appointed wallet

        // It owner should be the given address
        // It votingWallet should be the resolved appointed wallet
        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(carol, block.number - 1);
        assertEq(resolvedOwner, carol, "Should be carol");
        assertEq(votingWallet, carol, "Should be carol");

        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(david, block.number - 1);
        assertEq(resolvedOwner, david, "Should be david");
        assertEq(votingWallet, david, "Should be david");
    }

    function test_WhenTheGivenAddressIsAppointed2()
        external
        whenCallingResolveEncryptionAccountAtBlock
        givenTheResolvedOwnerWasListedOnResolveEncryptionAccountAtBlock
    {
        address resolvedOwner;
        address votingWallet;

        // It owner should be the resolved owner
        // It votingWallet should be the given address
        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(address(0x1234), block.number - 1);
        assertEq(resolvedOwner, alice, "Should be alice");
        assertEq(votingWallet, address(0x1234), "Should be 0x1234");

        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(address(0x2345), block.number - 1);
        assertEq(resolvedOwner, bob, "Should be bob");
        assertEq(votingWallet, address(0x2345), "Should be 0x2345");
    }

    function test_GivenTheResolvedOwnerWasNotListedOnResolveEncryptionAccountAtBlock()
        external
        whenCallingResolveEncryptionAccountAtBlock
    {
        address resolvedOwner;
        address votingWallet;

        // It should return a zero owner
        // It should return a zero votingWallet

        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(address(0), block.number - 1);
        assertEq(resolvedOwner, address(0), "Should be 0");
        assertEq(votingWallet, address(0), "Should be 0");

        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(address(0x5555), block.number - 1);
        assertEq(resolvedOwner, address(0), "Should be 0");
        assertEq(votingWallet, address(0), "Should be 0");

        (resolvedOwner, votingWallet) = signerList.resolveEncryptionAccountAtBlock(address(0xaaaa), block.number - 1);
        assertEq(resolvedOwner, address(0), "Should be 0");
        assertEq(votingWallet, address(0), "Should be 0");
    }

    modifier whenCallingGetEncryptionAgents() {
        _;
    }

    modifier whenCallingGetEncryptionRecipients() {
        _;
    }

    function test_GivenTheEncryptionRegistryHasNoAccounts() external whenCallingGetEncryptionRecipients {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        // No accounts registered a public key

        // It returns an empty list, even with signers
        address[] memory recipients = signerList.getEncryptionAgents();
        assertEq(recipients.length, 0, "Should be empty");

        // Empty the list
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 0));

        address[] memory rmSigners = new address[](4);
        rmSigners[0] = alice;
        rmSigners[1] = bob;
        rmSigners[2] = carol;
        rmSigners[3] = david;
        signerList.removeSigners(rmSigners);

        // It returns an empty list, without signers
        recipients = signerList.getEncryptionAgents();
        assertEq(recipients.length, 0, "Should be empty");
    }

    modifier givenTheEncryptionRegistryHasAccounts() {
        _;
    }

    function test_GivenNoOverlapBetweenRegistryAndSignerList()
        external
        whenCallingGetEncryptionRecipients
        givenTheEncryptionRegistryHasAccounts
    {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        // Old accounts register a public key or appoint
        vm.startPrank(alice);
        encryptionRegistry.setOwnPublicKey(bytes32(uint256(0x5555)));
        vm.startPrank(bob);
        encryptionRegistry.appointAgent(address(0x1234));
        vm.startPrank(address(0x1234));
        encryptionRegistry.setPublicKey(bob, bytes32(uint256(0x1234)));
        vm.startPrank(carol);
        encryptionRegistry.setOwnPublicKey(bytes32(uint256(0x5555)));
        vm.startPrank(david);
        encryptionRegistry.appointAgent(address(0x2345));
        vm.startPrank(address(0x2345));
        encryptionRegistry.setPublicKey(david, bytes32(uint256(0x2345)));

        // It returns an empty list
        address[] memory recipients = signerList.getEncryptionAgents();
        assertEq(recipients.length, 4, "Should have 4 members");
        assertEq(recipients[0], alice, "Should be alice");
        assertEq(recipients[1], address(0x1234), "Should be 1234");
        assertEq(recipients[2], carol, "Should be carol");
        assertEq(recipients[3], address(0x2345), "Should be 2345");

        vm.startPrank(alice);

        // Replace the list of signers
        address[] memory newSigners = new address[](4);
        newSigners[0] = address(0);
        newSigners[1] = address(1);
        newSigners[2] = address(2);
        newSigners[3] = address(3);
        signerList.addSigners(newSigners);

        address[] memory rmSigners = new address[](4);
        rmSigners[0] = alice;
        rmSigners[1] = bob;
        rmSigners[2] = carol;
        rmSigners[3] = david;
        signerList.removeSigners(rmSigners);

        // It returns an empty list
        recipients = signerList.getEncryptionAgents();
        assertEq(recipients.length, 0, "Should be empty");
    }

    function test_GivenSomeAddressesAreRegisteredEverywhere()
        external
        whenCallingGetEncryptionRecipients
        givenTheEncryptionRegistryHasAccounts
    {
        // It returns a list containing the overlapping addresses
        // It the result has the correct resolved addresses
        // It result does not contain unregistered addresses
        // It result does not contain unlisted addresses
        // It result does not contain non appointed addresses

        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        address[] memory newSigners = new address[](4);
        newSigners[0] = address(0x10);
        newSigners[1] = address(0x11);
        newSigners[2] = address(0x12);
        newSigners[3] = address(0x13);
        signerList.addSigners(newSigners);

        // Owner
        vm.startPrank(alice);
        encryptionRegistry.setOwnPublicKey(bytes32(uint256(0x5555)));
        // Appointing 1234
        vm.startPrank(bob);
        encryptionRegistry.appointAgent(address(0x1234));
        // Appointed
        vm.startPrank(address(0x1234));
        encryptionRegistry.setPublicKey(bob, bytes32(uint256(0x1234)));
        // Owner with no pubKey
        // vm.startPrank(carol);
        // encryptionRegistry.setOwnPublicKey(bytes32(uint256(0)));
        // Appointing 2345
        vm.startPrank(david);
        encryptionRegistry.appointAgent(address(0x2345));
        // Appointed with no pubKey
        // vm.startPrank(address(0x2345));
        // encryptionRegistry.setPublicKey(david, bytes32(uint256(0)));

        address[] memory recipients = signerList.getEncryptionAgents();
        assertEq(recipients.length, 3, "Should have 3 members");
        assertEq(recipients[0], alice, "Should be alice");
        assertEq(recipients[1], address(0x1234), "Should be 1234");
        // Carol didn't interact yet
        assertEq(recipients[2], address(0x2345), "Should be 2345");

        // Register the missing public keys
        vm.startPrank(carol);
        encryptionRegistry.setOwnPublicKey(bytes32(uint256(0x7777)));
        // Appointed by david
        vm.startPrank(address(0x2345));
        encryptionRegistry.setPublicKey(david, bytes32(uint256(0x2345)));

        // Updated list
        recipients = signerList.getEncryptionAgents();
        assertEq(recipients.length, 4, "Should have 4 members");
        assertEq(recipients[0], alice, "Should be alice");
        assertEq(recipients[1], address(0x1234), "Should be 1234");
        assertEq(recipients[2], address(0x2345), "Should be 2345");
        assertEq(recipients[3], carol, "Should be carol");
    }

    // Additional tests beyond SignerListTree.t.yaml

    function testFuzz_IsMemberIsFalseByDefault(uint256 _randomEntropy) public view {
        assertEq(
            signerList.isListed(vm.addr(uint256(keccak256(abi.encodePacked(_randomEntropy))))), false, "Should be false"
        );
    }
}
