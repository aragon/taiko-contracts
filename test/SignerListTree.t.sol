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
        encryptionRegistry = EncryptionRegistry(address(0));
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 0)))
            )
        );
    }

    function test_GivenADeployedContract() external {
        // It should refuse to initialize again
        encryptionRegistry = EncryptionRegistry(address(0));
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 0)))
            )
        );

        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        signerList.initialize(dao, signers, SignerList.Settings(EncryptionRegistry(address(0)), 0));
    }

    modifier givenANewInstance() {
        _;
    }

    modifier givenCallingInitialize() {
        _;
    }

    function test_GivenCallingInitialize() external givenANewInstance givenCallingInitialize {
        encryptionRegistry = EncryptionRegistry(address(0));
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 0)))
            )
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

        // It sets the new encryption registry
        vm.assertEq(address(reg), address(encryptionRegistry), "Incorrect address");

        // It sets the new minSignerListLength
        vm.assertEq(minSignerListLength, 0);

        // It should emit the SignersAdded event

        vm.expectEmit();
        emit SignersAdded({signers: signers});
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 0)))
            )
        );

        // It should emit a SignerListSettingsUpdated event

        vm.expectEmit();
        emit SignerListSettingsUpdated({encryptionRegistry: encryptionRegistry, minSignerListLength: 0});
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 0)))
            )
        );

        // It should set the right values in general

        // 2
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 0)))
            )
        );

        (reg, minSignerListLength) = signerList.settings();
        vm.assertEq(address(reg), address(encryptionRegistry), "Incorrect address");
        vm.assertEq(minSignerListLength, 0);
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(100)), false, "Should not be a signer");
        vm.assertEq(signerList.isListed(address(200)), false, "Should not be a signer");

        // 3
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 2)))
            )
        );

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

        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 1)))
            )
        );

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

    function test_RevertGiven_PassingMoreAddressesThanSupportedOnInitialize()
        external
        givenANewInstance
        givenCallingInitialize
    {
        // It should revert

        // 1
        signers = new address[](type(uint16).max + 1);

        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 0)))
            )
        );

        // 2
        signers = new address[](type(uint16).max + 10);

        vm.expectRevert(
            abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, type(uint16).max, type(uint16).max + 10)
        );
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 0)))
            )
        );
    }

    function test_RevertGiven_DuplicateAddressesOnInitialize() external givenANewInstance givenCallingInitialize {
        // It should revert

        // 1
        signers[2] = signers[1];
        vm.expectRevert();
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 2)))
            )
        );
    }

    function test_RevertWhen_EncryptionRegistryIsNotCompatibleOnInitialize()
        external
        givenANewInstance
        givenCallingInitialize
    {
        // It should revert

        // 1
        vm.expectRevert(InvalidEncryptionRegitry.selector);
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(
                    SignerList.initialize, (dao, signers, SignerList.Settings(EncryptionRegistry(address(alice)), 2))
                )
            )
        );

        // 2
        vm.expectRevert(InvalidEncryptionRegitry.selector);
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(
                    SignerList.initialize, (dao, signers, SignerList.Settings(EncryptionRegistry(address(bob)), 3))
                )
            )
        );

        // OK
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(
                    SignerList.initialize,
                    (dao, signers, SignerList.Settings(EncryptionRegistry(encryptionRegistry), 2))
                )
            )
        );
    }

    function test_RevertWhen_MinSignerListLengthIsBiggerThanTheListSizeOnInitialize()
        external
        givenANewInstance
        givenCallingInitialize
    {
        // It should revert

        // 1
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 4, 5));

        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(
                    SignerList.initialize, (dao, signers, SignerList.Settings(EncryptionRegistry(address(0)), 5))
                )
            )
        );

        // 2
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 4, 10));

        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(
                    SignerList.initialize, (dao, signers, SignerList.Settings(EncryptionRegistry(address(0)), 10))
                )
            )
        );

        // 3
        signers = new address[](5);
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 5, 15));

        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(
                    SignerList.initialize, (dao, signers, SignerList.Settings(EncryptionRegistry(address(0)), 15))
                )
            )
        );
    }

    modifier whenCallingUpdateSettings() {
        // Initialize
        encryptionRegistry = EncryptionRegistry(address(0));
        signerList = SignerList(
            createProxyAndCall(
                address(SIGNER_LIST_BASE),
                abi.encodeCall(SignerList.initialize, (dao, signers, SignerList.Settings(encryptionRegistry, 0)))
            )
        );

        _;
    }

    function test_WhenCallingUpdateSettings() external whenCallingUpdateSettings {
        encryptionRegistry = new EncryptionRegistry(Addresslist(address(0)));

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
        encryptionRegistry = new EncryptionRegistry(Addresslist(address(0)));
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

        encryptionRegistry = EncryptionRegistry(address(0));

        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(signerList),
                alice,
                UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID
            )
        );
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 0));
    }

    function test_RevertWhen_EncryptionRegistryIsNotCompatibleOnUpdateSettings() external whenCallingUpdateSettings {
        // It should revert

        vm.expectRevert(InvalidEncryptionRegitry.selector);
        signerList.updateSettings(SignerList.Settings(EncryptionRegistry(address(alice)), 0));
    }

    function test_RevertWhen_MinSignerListLengthIsBiggerThanTheListSizeOnUpdateSettings()
        external
        whenCallingUpdateSettings
    {
        // It should revert

        // 1
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 4, 15));
        signerList.updateSettings(SignerList.Settings(EncryptionRegistry(address(0)), 15));

        // 2
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 4, 20));
        signerList.updateSettings(SignerList.Settings(EncryptionRegistry(address(0)), 20));

        // 3
        signers = new address[](5);
        vm.expectRevert(abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, 5, 50));
        signerList.updateSettings(SignerList.Settings(EncryptionRegistry(address(0)), 50));
    }

    function test_WhenCallingSupportsInterface() external view {
        // It does not support the empty interface
        bool supported = multisig.supportsInterface(bytes4(0xffffffff));
        assertEq(supported, true, "Should not support the empty interface");

        // It supports IERC165Upgradeable
        supported = multisig.supportsInterface(type(IERC165Upgradeable).interfaceId);
        assertEq(supported, true, "Should support IERC165Upgradeable");

        // It supports Addresslist
        supported = multisig.supportsInterface(type(Addresslist).interfaceId);
        assertEq(supported, true, "Should support Addresslist");

        // It supports ISignerList
        supported = multisig.supportsInterface(type(ISignerList).interfaceId);
        assertEq(supported, true, "Should support ISignerList");
    }

    modifier whenCallingAddSigners() {
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

        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(100)), true, "Should be a signer");
        vm.assertEq(signerList.isListed(address(200)), false, "Should not be a signer");

        // 2
        newSigners[0] = address(200);
        signerList.addSigners(newSigners);

        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
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
        // It should revert

        address[] memory newSigners = new address[](1);
        newSigners[0] = address(100);

        vm.startPrank(bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID
            )
        );
        signerList.addSigners(newSigners);
    }

    function test_RevertGiven_PassingMoreAddressesThanSupportedOnUpdateSettings() external whenCallingAddSigners {
        // It should revert

        // 1
        address[] memory newSigners = new address[](type(uint8).max + 1);
        vm.expectRevert(
            abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, type(uint16).max, type(uint16).max + 1)
        );
        signerList.addSigners(newSigners);

        // 2
        newSigners = new address[](type(uint8).max + 10);
        vm.expectRevert(
            abi.encodeWithSelector(SignerListLengthOutOfBounds.selector, type(uint16).max, type(uint16).max + 10)
        );
        signerList.addSigners(newSigners);
    }

    function test_RevertGiven_DuplicateAddressesOnUpdateSettings() external whenCallingAddSigners {
        // It should revert

        // 1
        address[] memory newSigners = new address[](1);
        newSigners[0] = alice; // Alice is a signer already
        vm.expectRevert();
        signerList.addSigners(newSigners);

        // 2
        newSigners[0] = bob; // Bob is a signer already
        vm.expectRevert();
        signerList.addSigners(newSigners);

        // OK
        newSigners[0] = address(1234);
        vm.expectRevert();
        signerList.addSigners(newSigners);
    }

    modifier whenCallingRemoveSigners() {
        _;
    }

    function test_WhenCallingRemoveSigners() external whenCallingRemoveSigners {
        // It should more the given addresses
        // It should emit the SignersRemovedEvent
        vm.skip(true);
    }

    function test_RevertWhen_RemovingWithoutThePermission() external whenCallingRemoveSigners {
        // It should revert
        vm.skip(true);
    }

    function test_WhenRemovingAnUnlistedAddress() external whenCallingRemoveSigners {
        // It should continue gracefully
        vm.skip(true);
    }

    function test_RevertGiven_RemovingTooManyAddresses() external whenCallingRemoveSigners {
        // It should revert
        vm.skip(true);
    }

    modifier whenCallingIsListed() {
        _;
    }

    function test_GivenTheMemberIsListed() external whenCallingIsListed {
        // It returns true
        vm.skip(true);
    }

    function test_GivenTheMemberIsNotListed() external whenCallingIsListed {
        // It returns false
        vm.skip(true);
    }

    modifier whenCallingIsListedAtBlock() {
        _;
    }

    modifier givenTheMemberWasListed() {
        _;
    }

    function test_GivenTheMemberIsNotListedNow() external whenCallingIsListedAtBlock givenTheMemberWasListed {
        // It returns true
        vm.skip(true);
    }

    function test_GivenTheMemberIsListedNow() external whenCallingIsListedAtBlock givenTheMemberWasListed {
        // It returns true
        vm.skip(true);
    }

    modifier givenTheMemberWasNotListed() {
        _;
    }

    function test_GivenTheMemberIsDelistedNow() external whenCallingIsListedAtBlock givenTheMemberWasNotListed {
        // It returns false
        vm.skip(true);
    }

    function test_GivenTheMemberIsEnlistedNow() external whenCallingIsListedAtBlock givenTheMemberWasNotListed {
        // It returns false
        vm.skip(true);
    }

    modifier whenCallingResolveEncryptionAccountStatus() {
        _;
    }

    function test_GivenTheCallerIsAListedSigner() external whenCallingResolveEncryptionAccountStatus {
        // It ownerIsListed should be true
        // It isAppointed should be false
        vm.skip(true);
    }

    function test_GivenTheCallerIsAppointedByASigner() external whenCallingResolveEncryptionAccountStatus {
        // It ownerIsListed should be true
        // It isAppointed should be true
        vm.skip(true);
    }

    function test_GivenTheCallerIsNotListedOrAppointed() external whenCallingResolveEncryptionAccountStatus {
        // It ownerIsListed should be false
        // It isAppointed should be false
        vm.skip(true);
    }

    modifier whenCallingResolveEncryptionOwner() {
        _;
    }

    modifier givenTheResolvedOwnerIsListed() {
        _;
    }

    function test_WhenTheGivenAddressIsAppointed()
        external
        whenCallingResolveEncryptionOwner
        givenTheResolvedOwnerIsListed
    {
        // It owner should be the resolved owner
        // It appointedWallet should be the caller
        vm.skip(true);
    }

    function test_WhenTheGivenAddressIsNotAppointed()
        external
        whenCallingResolveEncryptionOwner
        givenTheResolvedOwnerIsListed
    {
        // It owner should be the caller
        // It appointedWallet should be resolved appointed wallet
        vm.skip(true);
    }

    function test_GivenTheResolvedOwnerIsNotListed() external whenCallingResolveEncryptionOwner {
        // It should return a zero owner
        // It should return a zero appointedWallet
        vm.skip(true);
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
