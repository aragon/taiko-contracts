// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";

contract EmergencyMultisigTest is Test {
    modifier givenANewlyDeployedContract() {
        _;
    }

    modifier givenCallingInitialize() {
        _;
    }

    function test_GivenCallingInitialize() external givenANewlyDeployedContract givenCallingInitialize {
        // It should initialize the first time
        // It should refuse to initialize again
        // It should set the DAO address
        // It should set the minApprovals
        // It should set onlyListed
        // It should set signerList
        // It should set proposalExpirationPeriod
        // It should emit MultisigSettingsUpdated
        vm.skip(true);
    }

    function test_RevertWhen_MinApprovalsIsGreaterThanSignerListLengthOnInitialize()
        external
        givenANewlyDeployedContract
        givenCallingInitialize
    {
        // It should revert
        // It should revert (with onlyListed false)
        // It should not revert otherwise
        vm.skip(true);
    }

    function test_RevertWhen_MinApprovalsIsZeroOnInitialize()
        external
        givenANewlyDeployedContract
        givenCallingInitialize
    {
        // It should revert
        // It should revert (with onlyListed false)
        // It should not revert otherwise
        vm.skip(true);
    }

    function test_RevertWhen_SignerListIsInvalidOnInitialize()
        external
        givenANewlyDeployedContract
        givenCallingInitialize
    {
        // It should revert
        vm.skip(true);
    }

    function test_WhenCallingUpgradeTo() external {
        // It should revert when called without the permission
        // It should work when called with the permission
        vm.skip(true);
    }

    function test_WhenCallingUpgradeToAndCall() external {
        // It should revert when called without the permission
        // It should work when called with the permission
        vm.skip(true);
    }

    function test_WhenCallingSupportsInterface() external {
        // It does not support the empty interface
        // It supports IERC165Upgradeable
        // It supports IPlugin
        // It supports IProposal
        // It supports IEmergencyMultisig
        vm.skip(true);
    }

    modifier whenCallingUpdateSettings() {
        _;
    }

    function test_WhenCallingUpdateSettings() external whenCallingUpdateSettings {
        // It should set the minApprovals
        // It should set onlyListed
        // It should set signerList
        // It should set proposalExpirationPeriod
        // It should emit MultisigSettingsUpdated
        vm.skip(true);
    }

    function test_RevertGiven_CallerHasNoPermission() external whenCallingUpdateSettings {
        // It should revert
        // It otherwise it should just work
        vm.skip(true);
    }

    function test_RevertWhen_MinApprovalsIsGreaterThanSignerListLengthOnUpdateSettings()
        external
        whenCallingUpdateSettings
    {
        // It should revert
        // It should revert (with onlyListed false)
        // It should not revert otherwise
        vm.skip(true);
    }

    function test_RevertWhen_MinApprovalsIsZeroOnUpdateSettings() external whenCallingUpdateSettings {
        // It should revert
        // It should revert (with onlyListed false)
        // It should not revert otherwise
        vm.skip(true);
    }

    function test_RevertWhen_SignerListIsInvalidOnUpdateSettings() external whenCallingUpdateSettings {
        // It should revert
        vm.skip(true);
    }

    modifier whenCallingCreateProposal() {
        _;
    }

    function test_WhenCallingCreateProposal() external whenCallingCreateProposal {
        // It increments the proposal counter
        // It creates and return unique proposal IDs
        // It emits the ProposalCreated event
        // It creates a proposal with the given values
        vm.skip(true);
    }

    function test_GivenSettingsChangedOnTheSameBlock() external whenCallingCreateProposal {
        // It reverts
        // It does not revert otherwise
        vm.skip(true);
    }

    function test_GivenOnlyListedIsFalse() external whenCallingCreateProposal {
        // It allows anyone to create
        vm.skip(true);
    }

    modifier givenOnlyListedIsTrue() {
        _;
    }

    function test_GivenCreationCallerIsNotListedOrAppointed()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It reverts
        vm.skip(true);
    }

    function test_GivenCreationCallerIsAppointedByAFormerSigner()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It reverts
        vm.skip(true);
    }

    function test_GivenCreationCallerIsListedAndSelfAppointed()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It creates the proposal
        vm.skip(true);
    }

    function test_GivenCreationCallerIsListedAppointingSomeoneElseNow()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It creates the proposal
        vm.skip(true);
    }

    function test_GivenCreationCallerIsAppointedByACurrentSigner()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It creates the proposal
        vm.skip(true);
    }

    function test_GivenApproveProposalIsTrue() external whenCallingCreateProposal {
        // It creates and calls approval in one go
        vm.skip(true);
    }

    function test_GivenApproveProposalIsFalse() external whenCallingCreateProposal {
        // It only creates the proposal
        vm.skip(true);
    }

    function test_WhenCallingHashActions() external {
        // It returns the right result
        // It reacts to any of the values changing
        vm.skip(true);
    }

    modifier givenTheProposalIsNotCreated() {
        _;
    }

    function test_WhenCallingGetProposalUncreated() external givenTheProposalIsNotCreated {
        // It should return empty values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveUncreated() external givenTheProposalIsNotCreated {
        // It canApprove should return false (when currently listed and self appointed)
        // It approve should revert (when currently listed and self appointed)
        // It canApprove should return false (when currently listed, appointing someone else now)
        // It approve should revert (when currently listed, appointing someone else now)
        // It canApprove should return false (when appointed by a listed signer)
        // It approve should revert (when appointed by a listed signer)
        // It canApprove should return false (when currently unlisted and unappointed)
        // It approve should revert (when currently unlisted and unappointed)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedUncreated() external givenTheProposalIsNotCreated {
        // It hasApproved should always return false
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteUncreated() external givenTheProposalIsNotCreated {
        // It canExecute should always return false
        vm.skip(true);
    }

    modifier givenTheProposalIsOpen() {
        _;
    }

    function test_WhenCallingGetProposalOpen() external givenTheProposalIsOpen {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveOpen() external givenTheProposalIsOpen {
        // It canApprove should return true (when listed on creation, self appointed now)
        // It approve should work (when listed on creation, self appointed now)
        // It approve should emit an event (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It canApprove should return true (when currently appointed by a signer listed on creation)
        // It approve should work (when currently appointed by a signer listed on creation)
        // It approve should emit an event (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedOpen() external givenTheProposalIsOpen {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteOpen() external givenTheProposalIsOpen {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)
        // It execute should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    modifier givenTheProposalWasApprovedByTheAddress() {
        _;
    }

    function test_WhenCallingGetProposalApproved() external givenTheProposalWasApprovedByTheAddress {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveApproved() external givenTheProposalWasApprovedByTheAddress {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It approve should revert (when currently appointed by a signer listed on creation)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedApproved() external givenTheProposalWasApprovedByTheAddress {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteApproved() external givenTheProposalWasApprovedByTheAddress {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It execute should revert (when currently appointed by a signer listed on creation)
        vm.skip(true);
    }

    modifier givenTheProposalPassed() {
        _;
    }

    function test_WhenCallingGetProposalPassed() external givenTheProposalPassed {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApprovePassed() external givenTheProposalPassed {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedPassed() external givenTheProposalPassed {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteWithModifiedDataPassed() external givenTheProposalPassed {
        // It execute should revert, always
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecutePassed() external givenTheProposalPassed {
        // It canExecute should return true, always
        // It execute should work, always
        // It execute should emit an event, always
        // It execute recreates the proposal on the destination plugin
        // It The parameters of the recreated proposal match the hash of the executed one
        // It A ProposalCreated event is emitted on the destination plugin
        vm.skip(true);
    }

    modifier givenTheProposalIsAlreadyExecuted() {
        _;
    }

    function test_WhenCallingGetProposalExecuted() external givenTheProposalIsAlreadyExecuted {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveExecuted() external givenTheProposalIsAlreadyExecuted {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedExecuted() external givenTheProposalIsAlreadyExecuted {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteExecuted() external givenTheProposalIsAlreadyExecuted {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)
        // It execute should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    modifier givenTheProposalExpired() {
        _;
    }

    function test_WhenCallingGetProposalExpired() external givenTheProposalExpired {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveExpired() external givenTheProposalExpired {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedExpired() external givenTheProposalExpired {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteExpired() external givenTheProposalExpired {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)
        // It execute should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }
}
