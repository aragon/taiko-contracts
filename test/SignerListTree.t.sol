// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";

contract SignerListTest is Test {
    function test_WhenDeployingTheContract() external {
        // It should initialize normally
        vm.skip(true);
    }

    function test_GivenADeployedContract() external {
        // It should refuse to initialize again
        vm.skip(true);
    }

    modifier givenANewInstance() {
        _;
    }

    modifier givenCallingInitialize() {
        _;
    }

    function test_GivenCallingInitialize() external givenANewInstance givenCallingInitialize {
        // It should set the DAO address
        // It should set the addresses as signers
        // It settings should match the given ones
        // It should emit the SignersAdded event
        // It should emit the SignerListSettingsUpdated event
        vm.skip(true);
    }

    function test_RevertGiven_PassingMoreAddressesThanSupported() external givenANewInstance givenCallingInitialize {
        // It should revert
        vm.skip(true);
    }

    modifier whenCallingUpdateSettings() {
        _;
    }

    function test_WhenCallingUpdateSettings() external whenCallingUpdateSettings {
        // It set the new encryption registry
        // It set the new minSignerListLength
        // It should emit a SignerListSettingsUpdated event
        vm.skip(true);
    }

    function test_RevertWhen_UpdateSettingsWithoutThePermission() external whenCallingUpdateSettings {
        // It should revert
        vm.skip(true);
    }

    function test_RevertWhen_EncryptionRegistryIsNotCompatible() external whenCallingUpdateSettings {
        // It should revert
        vm.skip(true);
    }

    function test_RevertWhen_SettingAMinSignerListLengthLowerThanTheCurrentListSize()
        external
        whenCallingUpdateSettings
    {
        // It should revert
        vm.skip(true);
    }

    function test_WhenCallingSupportsInterface() external {
        // It does not support the empty interface
        // It supports IERC165Upgradeable
        // It supports IPlugin
        // It supports IProposal
        // It supports IMultisig
        vm.skip(true);
    }

    modifier whenCallingAddSigners() {
        _;
    }

    function test_WhenCallingAddSigners() external whenCallingAddSigners {
        // It should append the new addresses to the list
        // It should emit the SignersAddedEvent
        vm.skip(true);
    }

    function test_RevertWhen_AddingWithoutThePermission() external whenCallingAddSigners {
        // It should revert
        vm.skip(true);
    }

    function test_RevertGiven_PassingMoreAddressesThanAllowed() external whenCallingAddSigners {
        // It should revert
        vm.skip(true);
    }

    function test_RevertGiven_DuplicateAddresses() external whenCallingAddSigners {
        // It should revert
        vm.skip(true);
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
