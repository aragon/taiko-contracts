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

        signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;
    }

    function test_WhenDeployingTheContract() external {
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

    modifier whenCallingResolveEncryptionAccountStatus() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 2));

        // Remove Carol and David
        address[] memory rmSigners = new address[](2);
        rmSigners[0] = carol;
        rmSigners[1] = david;
        signerList.removeSigners(rmSigners);

        // Alice (owner) appoints david
        encryptionRegistry.appointWallet(david);

        // Bob is the owner

        _;
    }

    function test_GivenTheCallerIsAListedSigner() external whenCallingResolveEncryptionAccountStatus {
        // 1
        (bool ownerIsListed, bool appointed) = signerList.resolveEncryptionAccountStatus(alice);

        // It ownerIsListed should be true
        assertEq(ownerIsListed, true, "The owner should be listed");

        // It isAppointed should be false
        assertEq(appointed, false, "Should not be appointed");

        // 2
        (ownerIsListed, appointed) = signerList.resolveEncryptionAccountStatus(bob);

        // It ownerIsListed should be true
        assertEq(ownerIsListed, true, "The owner should be listed");

        // It isAppointed should be false
        assertEq(appointed, false, "Should not be appointed");
    }

    function test_GivenTheCallerIsAppointedByASigner() external whenCallingResolveEncryptionAccountStatus {
        (bool ownerIsListed, bool appointed) = signerList.resolveEncryptionAccountStatus(david);

        // It ownerIsListed should be true
        assertEq(ownerIsListed, true, "The owner should be listed");

        // It isAppointed should be true
        assertEq(appointed, true, "Should be appointed");
    }

    function test_GivenTheCallerIsNotListedOrAppointed() external whenCallingResolveEncryptionAccountStatus {
        // 1
        (bool ownerIsListed, bool appointed) = signerList.resolveEncryptionAccountStatus(carol);

        // It ownerIsListed should be false
        assertEq(ownerIsListed, false, "The owner should be listed");

        // It isAppointed should be false
        assertEq(appointed, false, "Should be appointed");

        // 2
        (ownerIsListed, appointed) = signerList.resolveEncryptionAccountStatus(address(1234));

        // It ownerIsListed should be false
        assertEq(ownerIsListed, false, "The owner should not be listed");

        // It isAppointed should be false
        assertEq(appointed, false, "Should not be appointed");
    }

    modifier whenCallingResolveEncryptionOwner() {
        // Alice (owner) appoints address(0x1234)
        encryptionRegistry.appointWallet(address(0x1234));

        // Bob (owner) appoints address(0x2345)
        vm.startPrank(bob);
        encryptionRegistry.appointWallet(address(0x2345));

        vm.startPrank(alice);

        // Carol is owner
        // David is owner

        _;
    }

    modifier givenTheResolvedOwnerIsListedOnResolveEncryptionOwner() {
        _;
    }

    function test_WhenTheGivenAddressIsTheOwner()
        external
        whenCallingResolveEncryptionOwner
        givenTheResolvedOwnerIsListedOnResolveEncryptionOwner
    {
        address resolvedOwner;

        // It should return the given address
        resolvedOwner = signerList.resolveEncryptionOwner(alice);
        assertEq(resolvedOwner, alice, "Should be alice");

        resolvedOwner = signerList.resolveEncryptionOwner(bob);
        assertEq(resolvedOwner, bob, "Should be bob");

        resolvedOwner = signerList.resolveEncryptionOwner(carol);
        assertEq(resolvedOwner, carol, "Should be carol");

        resolvedOwner = signerList.resolveEncryptionOwner(david);
        assertEq(resolvedOwner, david, "Should be david");
    }

    function test_WhenTheGivenAddressIsAppointedByTheOwner()
        external
        whenCallingResolveEncryptionOwner
        givenTheResolvedOwnerIsListedOnResolveEncryptionOwner
    {
        address resolvedOwner;

        // It should return the resolved owner
        resolvedOwner = signerList.resolveEncryptionOwner(address(0x1234));
        assertEq(resolvedOwner, alice, "Should be alice");

        resolvedOwner = signerList.resolveEncryptionOwner(address(0x2345));
        assertEq(resolvedOwner, bob, "Should be bob");
    }

    function test_GivenTheResolvedOwnerIsNotListedOnResolveEncryptionOwner()
        external
        whenCallingResolveEncryptionOwner
    {
        address resolvedOwner;

        // It should return a zero value
        resolvedOwner = signerList.resolveEncryptionOwner(address(0x3456));
        assertEq(resolvedOwner, address(0), "Should be zero");

        resolvedOwner = signerList.resolveEncryptionOwner(address(0x4567));
        assertEq(resolvedOwner, address(0), "Should be zero");
    }

    modifier whenCallingResolveEncryptionAccount() {
        // Alice (owner) appoints address(0x1234)
        encryptionRegistry.appointWallet(address(0x1234));

        // Bob (owner) appoints address(0x2345)
        vm.startPrank(bob);
        encryptionRegistry.appointWallet(address(0x2345));

        vm.startPrank(alice);

        // Carol is owner
        // David is owner

        _;
    }

    modifier givenTheResolvedOwnerIsListedOnResolveEncryptionAccount() {
        _;
    }

    function test_WhenTheGivenAddressIsAppointed()
        external
        whenCallingResolveEncryptionAccount
        givenTheResolvedOwnerIsListedOnResolveEncryptionAccount
    {
        address resolvedOwner;
        address appointedWallet;

        // It owner should be the resolved owner
        // It appointedWallet should be the given address
        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(address(0x1234));
        assertEq(resolvedOwner, alice, "Should be alice");
        assertEq(appointedWallet, address(0x1234), "Should be 0x1234");

        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(address(0x2345));
        assertEq(resolvedOwner, bob, "Should be bob");
        assertEq(appointedWallet, address(0x2345), "Should be 0x2345");
    }

    function test_WhenTheGivenAddressIsNotAppointed()
        external
        whenCallingResolveEncryptionAccount
        givenTheResolvedOwnerIsListedOnResolveEncryptionAccount
    {
        address resolvedOwner;
        address appointedWallet;

        // 1 - owner appoints

        // It owner should be the given address
        // It appointedWallet should be the resolved appointed wallet
        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(alice);
        assertEq(resolvedOwner, alice, "Should be alice");
        assertEq(appointedWallet, address(0x1234), "Should be 0x1234");
        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(address(0x1234));
        assertEq(resolvedOwner, alice, "Should be alice");
        assertEq(appointedWallet, address(0x1234), "Should be 0x1234");

        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(bob);
        assertEq(resolvedOwner, bob, "Should be bob");
        assertEq(appointedWallet, address(0x2345), "Should be 0x2345");
        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(address(0x2345));
        assertEq(resolvedOwner, bob, "Should be bob");
        assertEq(appointedWallet, address(0x2345), "Should be 0x2345");

        // 2 - No appointed wallet

        // It owner should be the given address
        // It appointedWallet should be the resolved appointed wallet
        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(carol);
        assertEq(resolvedOwner, carol, "Should be carol");
        assertEq(appointedWallet, carol, "Should be carol");

        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(david);
        assertEq(resolvedOwner, david, "Should be david");
        assertEq(appointedWallet, david, "Should be david");
    }

    function test_GivenTheResolvedOwnerIsNotListedOnResolveEncryptionAccount()
        external
        whenCallingResolveEncryptionAccount
    {
        address resolvedOwner;
        address appointedWallet;

        // It should return a zero owner
        // It should return a zero appointedWallet

        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(address(0));
        assertEq(resolvedOwner, address(0), "Should be 0");
        assertEq(appointedWallet, address(0), "Should be 0");

        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(address(0x5555));
        assertEq(resolvedOwner, address(0), "Should be 0");
        assertEq(appointedWallet, address(0), "Should be 0");

        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(address(0xaaaa));
        assertEq(resolvedOwner, address(0), "Should be 0");
        assertEq(appointedWallet, address(0), "Should be 0");

        // Formerly a signer
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 1));

        // Remove Bob (appointed 0x2345) and David
        address[] memory rmSigners = new address[](2);
        rmSigners[0] = bob;
        rmSigners[1] = david;
        signerList.removeSigners(rmSigners);

        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(bob);
        assertEq(resolvedOwner, address(0), "Should be 0");
        assertEq(appointedWallet, address(0), "Should be 0");

        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(address(0x2345));
        assertEq(resolvedOwner, address(0), "Should be 0");
        assertEq(appointedWallet, address(0), "Should be 0");

        (resolvedOwner, appointedWallet) = signerList.resolveEncryptionAccount(david);
        assertEq(resolvedOwner, address(0), "Should be 0");
        assertEq(appointedWallet, address(0), "Should be 0");
    }

    modifier whenCallingGetEncryptionRecipients() {
        _;
    }

    function test_GivenTheEncryptionRegistryHasNoAccounts() external whenCallingGetEncryptionRecipients {
        // It returns an empty list, even with signers
        // It returns an empty list, without signers
        vm.skip(true);
    }

    modifier givenTheEncryptionRegistryHasAccounts() {
        _;
    }

    function test_GivenNoOverlapBetweenRegistryAndSignerList()
        external
        whenCallingGetEncryptionRecipients
        givenTheEncryptionRegistryHasAccounts
    {
        // It returns an empty list
        vm.skip(true);
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
        vm.skip(true);
    }
}
