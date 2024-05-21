// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

import {ProposalUpgradeable} from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {IMultisig} from "./interfaces/IMultisig.sol";
import {OptimisticTokenVotingPlugin} from "./OptimisticTokenVotingPlugin.sol";

uint64 constant MULTISIG_PROPOSAL_EXPIRATION_PERIOD = 10 days;

/// @title Multisig - Release 1, Build 1
/// @author Aragon Association - 2022-2024
/// @notice The on-chain multisig governance plugin in which a proposal passes if X out of Y approvals are met.
contract Multisig is IMultisig, IMembership, PluginUUPSUpgradeable, ProposalUpgradeable, Addresslist {
    using SafeCastUpgradeable for uint256;

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param approvals The number of approvals casted.
    /// @param parameters The proposal-specific approve settings at the time of the proposal creation.
    /// @param approvers The approves casted by the approvers.
    /// @param destinationActions The actions to be executed by the destination plugin when the proposal passes.
    /// @param metadataURI The URI on which human readable data ca ben retrieved
    /// @param destinationPlugin The address of the plugin where the proposal will be created if it passes.
    struct Proposal {
        bool executed;
        uint16 approvals;
        ProposalParameters parameters;
        mapping(address => bool) approvers;
        IDAO.Action[] destinationActions;
        bytes metadataURI;
        OptimisticTokenVotingPlugin destinationPlugin;
    }

    /// @notice A container for the proposal parameters.
    /// @param minApprovals The number of approvals required.
    /// @param snapshotBlock The number of the block prior to the proposal creation.
    /// @param expirationDate The timestamp after which non-executed proposals expire.
    struct ProposalParameters {
        uint16 minApprovals;
        uint64 snapshotBlock;
        uint64 expirationDate;
    }

    /// @notice A container for the plugin settings.
    /// @param onlyListed Whether only listed addresses can create a proposal or not.
    /// @param minApprovals The minimal number of approvals required for a proposal to pass.
    /// @param destinationProposalDuration The minimum duration that the destination plugin will enforce.
    struct MultisigSettings {
        bool onlyListed;
        uint16 minApprovals;
        uint64 destinationProposalDuration;
    }

    /// @notice The ID of the permission required to call the `addAddresses` and `removeAddresses` functions.
    bytes32 public constant UPDATE_MULTISIG_SETTINGS_PERMISSION_ID = keccak256("UPDATE_MULTISIG_SETTINGS_PERMISSION");

    /// @notice A mapping between proposal IDs and proposal information.
    mapping(uint256 => Proposal) internal proposals;

    /// @notice The current plugin settings.
    MultisigSettings public multisigSettings;

    /// @notice Keeps track at which block number the multisig settings have been changed the last time.
    /// @dev This variable prevents a proposal from being created in the same block in which the multisig settings change.
    uint64 public lastMultisigSettingsChange;

    /// @notice Thrown when a sender is not allowed to create a proposal.
    /// @param sender The sender address.
    error ProposalCreationForbidden(address sender);

    /// @notice Thrown if an approver is not allowed to cast an approve. This can be because the proposal
    /// - is not open,
    /// - was executed, or
    /// - the approver is not on the address list
    /// @param proposalId The ID of the proposal.
    /// @param sender The address of the sender.
    error ApprovalCastForbidden(uint256 proposalId, address sender);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);

    /// @notice Thrown if the minimal approvals value is out of bounds (less than 1 or greater than the number of members in the address list).
    /// @param limit The maximal value.
    /// @param actual The actual value.
    error MinApprovalsOutOfBounds(uint16 limit, uint16 actual);

    /// @notice Thrown if the address list length is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error AddresslistLengthOutOfBounds(uint16 limit, uint256 actual);

    /// @notice Emitted when a proposal is approve by an approver.
    /// @param proposalId The ID of the proposal.
    /// @param approver The approver casting the approve.
    event Approved(uint256 indexed proposalId, address indexed approver);

    /// @notice Emitted when a proposal passes and is relayed to the destination plugin.
    /// @param proposalId The ID of the proposal.
    event Executed(uint256 indexed proposalId);

    /// @notice Emitted when the plugin settings are set.
    /// @param onlyListed Whether only listed addresses can create a proposal.
    /// @param minApprovals The minimum amount of approvals needed to pass a proposal.
    /// @param destinationProposalDuration The minimum duration (in seconds) that will be required on the destination plugin
    event MultisigSettingsUpdated(bool onlyListed, uint16 indexed minApprovals, uint64 destinationProposalDuration);

    /// @notice Initializes Release 1, Build 2.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _members The addresses of the initial members to be added.
    /// @param _multisigSettings The multisig settings.
    function initialize(IDAO _dao, address[] calldata _members, MultisigSettings calldata _multisigSettings)
        external
        initializer
    {
        __PluginUUPSUpgradeable_init(_dao);

        if (_members.length > type(uint16).max) {
            revert AddresslistLengthOutOfBounds({limit: type(uint16).max, actual: _members.length});
        }

        _addAddresses(_members);
        emit MembersAdded({members: _members});

        _updateMultisigSettings(_multisigSettings);
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(PluginUUPSUpgradeable, ProposalUpgradeable)
        returns (bool)
    {
        return _interfaceId == type(IMultisig).interfaceId || _interfaceId == type(Addresslist).interfaceId
            || _interfaceId == type(IMembership).interfaceId || super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc IMultisig
    function addAddresses(address[] calldata _members) external auth(UPDATE_MULTISIG_SETTINGS_PERMISSION_ID) {
        uint256 newAddresslistLength = addresslistLength() + _members.length;

        // Check if the new address list length would be greater than `type(uint16).max`, the maximal number of approvals.
        if (newAddresslistLength > type(uint16).max) {
            revert AddresslistLengthOutOfBounds({limit: type(uint16).max, actual: newAddresslistLength});
        }

        _addAddresses(_members);

        emit MembersAdded({members: _members});
    }

    /// @inheritdoc IMultisig
    function removeAddresses(address[] calldata _members) external auth(UPDATE_MULTISIG_SETTINGS_PERMISSION_ID) {
        uint16 newAddresslistLength = uint16(addresslistLength() - _members.length);

        // Check if the new address list length would become less than the current minimum number of approvals required.
        if (newAddresslistLength < multisigSettings.minApprovals) {
            revert MinApprovalsOutOfBounds({limit: multisigSettings.minApprovals, actual: newAddresslistLength});
        }

        _removeAddresses(_members);

        emit MembersRemoved({members: _members});
    }

    /// @notice Updates the plugin settings.
    /// @param _multisigSettings The new settings.
    function updateMultisigSettings(MultisigSettings calldata _multisigSettings)
        external
        auth(UPDATE_MULTISIG_SETTINGS_PERMISSION_ID)
    {
        _updateMultisigSettings(_multisigSettings);
    }

    /// @notice Creates a new multisig proposal.
    /// @param _metadataURI The metadataURI of the proposal.
    /// @param _destinationActions The actions that will be executed after the proposal passes.
    /// @param _destinationPlugin The address of the plugin to forward the proposal to when it passes.
    /// @param _approveProposal If `true`, the sender will approve the proposal.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata _metadataURI,
        IDAO.Action[] calldata _destinationActions,
        OptimisticTokenVotingPlugin _destinationPlugin,
        bool _approveProposal
    ) external returns (uint256 proposalId) {
        if (multisigSettings.onlyListed && !isListed(msg.sender)) {
            revert ProposalCreationForbidden(msg.sender);
        }

        uint64 snapshotBlock;
        unchecked {
            snapshotBlock = block.number.toUint64() - 1; // The snapshot block must be mined already to protect the transaction against backrunning transactions causing census changes.
        }

        // Revert if the settings have been changed in the same block as this proposal should be created in.
        // This prevents a malicious party from voting with previous addresses and the new settings.
        if (lastMultisigSettingsChange > snapshotBlock) {
            revert ProposalCreationForbidden(msg.sender);
        }

        uint64 _expirationDate = block.timestamp.toUint64() + MULTISIG_PROPOSAL_EXPIRATION_PERIOD;
        proposalId = _createProposal({
            _creator: msg.sender,
            _metadata: _metadataURI,
            _startDate: block.timestamp.toUint64(),
            _endDate: _expirationDate,
            _actions: _destinationActions,
            _allowFailureMap: 0
        });

        // Create the proposal
        Proposal storage proposal_ = proposals[proposalId];
        proposal_.metadataURI = _metadataURI;
        proposal_.destinationPlugin = _destinationPlugin;

        proposal_.parameters.snapshotBlock = snapshotBlock;
        proposal_.parameters.expirationDate = _expirationDate;
        proposal_.parameters.minApprovals = multisigSettings.minApprovals;

        for (uint256 i; i < _destinationActions.length;) {
            proposal_.destinationActions.push(_destinationActions[i]);
            unchecked {
                ++i;
            }
        }

        if (_approveProposal) {
            approve(proposalId, false);
        }
    }

    /// @inheritdoc IMultisig
    function approve(uint256 _proposalId, bool _tryExecution) public {
        address approver = msg.sender;
        if (!_canApprove(_proposalId, approver)) {
            revert ApprovalCastForbidden(_proposalId, approver);
        }

        Proposal storage proposal_ = proposals[_proposalId];

        // As the list can never become more than type(uint16).max(due to addAddresses check)
        // It's safe to use unchecked as it would never overflow.
        unchecked {
            proposal_.approvals += 1;
        }

        proposal_.approvers[approver] = true;

        emit Approved({proposalId: _proposalId, approver: approver});

        if (_tryExecution && _canExecute(_proposalId)) {
            _execute(_proposalId);
        }
    }

    /// @inheritdoc IMultisig
    function canApprove(uint256 _proposalId, address _account) external view returns (bool) {
        return _canApprove(_proposalId, _account);
    }

    /// @inheritdoc IMultisig
    function canExecute(uint256 _proposalId) external view returns (bool) {
        return _canExecute(_proposalId);
    }

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return executed Whether the proposal is executed or not.
    /// @return approvals The number of approvals casted.
    /// @return parameters The parameters of the proposal vote.
    /// @return metadataURI The URI at which the corresponding human readable data can be found.
    /// @return destinationActions The actions to be executed by the destination plugin after the proposal passes.
    /// @return destinationPlugin The address of the plugin where the proposal will be forwarded to when executed.
    function getProposal(uint256 _proposalId)
        public
        view
        returns (
            bool executed,
            uint16 approvals,
            ProposalParameters memory parameters,
            bytes memory metadataURI,
            IDAO.Action[] memory destinationActions,
            OptimisticTokenVotingPlugin destinationPlugin
        )
    {
        Proposal storage proposal_ = proposals[_proposalId];

        executed = proposal_.executed;
        approvals = proposal_.approvals;
        parameters = proposal_.parameters;
        metadataURI = proposal_.metadataURI;
        destinationActions = proposal_.destinationActions;
        destinationPlugin = proposal_.destinationPlugin;
    }

    /// @inheritdoc IMultisig
    function hasApproved(uint256 _proposalId, address _account) public view returns (bool) {
        return proposals[_proposalId].approvers[_account];
    }

    /// @inheritdoc IMultisig
    function execute(uint256 _proposalId) public {
        if (!_canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }

        _execute(_proposalId);
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        return isListed(_account);
    }

    /// @notice Internal function to execute a vote. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    function _execute(uint256 _proposalId) internal {
        Proposal storage proposal_ = proposals[_proposalId];

        proposal_.executed = true;
        emit Executed(_proposalId);

        proposal_.destinationPlugin.createProposal(
            proposal_.metadataURI,
            proposal_.destinationActions,
            0, // allowFailureMap, no single action may fail
            multisigSettings.destinationProposalDuration
        );
    }

    /// @notice Internal function to check if an account can approve. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account to check.
    /// @return Returns `true` if the given account can approve on a certain proposal and `false` otherwise.
    function _canApprove(uint256 _proposalId, address _account) internal view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        if (!_isProposalOpen(proposal_)) {
            // The proposal is executed or expired
            return false;
        }

        if (!isListedAtBlock(_account, proposal_.parameters.snapshotBlock)) {
            // The approver has no voting power.
            return false;
        }

        if (proposal_.approvers[_account]) {
            // The approver has already approved
            return false;
        }

        return true;
    }

    /// @notice Internal function to check if a proposal can be executed. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the proposal can be executed and `false` otherwise.
    function _canExecute(uint256 _proposalId) internal view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // Verify that the proposal has not been executed or expired.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }

        return proposal_.approvals >= proposal_.parameters.minApprovals;
    }

    /// @notice Internal function to check if a proposal is still open.
    /// @param proposal_ The proposal struct.
    /// @return True if the proposal vote is open, false otherwise.
    function _isProposalOpen(Proposal storage proposal_) internal view returns (bool) {
        uint64 currentTimestamp64 = block.timestamp.toUint64();
        return !proposal_.executed && proposal_.parameters.expirationDate > currentTimestamp64;
    }

    /// @notice Internal function to update the plugin settings.
    /// @param _multisigSettings The new settings.
    function _updateMultisigSettings(MultisigSettings calldata _multisigSettings) internal {
        uint16 addresslistLength_ = uint16(addresslistLength());

        if (_multisigSettings.minApprovals > addresslistLength_) {
            revert MinApprovalsOutOfBounds({limit: addresslistLength_, actual: _multisigSettings.minApprovals});
        }

        if (_multisigSettings.minApprovals < 1) {
            revert MinApprovalsOutOfBounds({limit: 1, actual: _multisigSettings.minApprovals});
        }

        multisigSettings = _multisigSettings;
        lastMultisigSettingsChange = block.number.toUint64();

        emit MultisigSettingsUpdated({
            onlyListed: _multisigSettings.onlyListed,
            minApprovals: _multisigSettings.minApprovals,
            destinationProposalDuration: _multisigSettings.destinationProposalDuration
        });
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[47] private __gap;
}
