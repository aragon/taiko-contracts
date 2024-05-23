// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

import {ProposalUpgradeable} from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {IEmergencyMultisig} from "./interfaces/IEmergencyMultisig.sol";
import {OptimisticTokenVotingPlugin} from "./OptimisticTokenVotingPlugin.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

uint64 constant EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD = 8 days;

/// @title Multisig - Release 1, Build 1
/// @author Aragon Association - 2022-2024
/// @notice The on-chain multisig governance plugin in which a proposal passes if X out of Y approvals are met.
contract EmergencyMultisig is IEmergencyMultisig, IMembership, PluginUUPSUpgradeable, ProposalUpgradeable {
    using SafeCastUpgradeable for uint256;

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param approvals The number of approvals casted.
    /// @param parameters The proposal-specific approve settings at the time of the proposal creation.
    /// @param approvers The approves casted by the approvers.
    /// @param encryptedPayloadURI The IPFS URI where a JSON with the encrypted payload is pinned
    /// @param destinationActionsHash The hash of the serialized list of actions to be executed
    /// @param destinationPlugin The address of the plugin where the proposal will be created if it passes.
    struct Proposal {
        bool executed;
        uint16 approvals;
        ProposalParameters parameters;
        mapping(address => bool) approvers;
        bytes encryptedPayloadURI;
        bytes32 destinationActionsHash;
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
    /// @param addresslistSource The contract where the list of signers is defined
    struct MultisigSettings {
        bool onlyListed;
        uint16 minApprovals;
        Addresslist addresslistSource;
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

    /// @notice Thrown if the actions passed for execution don't match the expected hash.
    /// @param proposalId The ID of the proposal.
    error InvalidActions(uint256 proposalId);

    /// @notice Thrown if the minimal approvals value is out of bounds (less than 1 or greater than the number of members in the address list).
    /// @param limit The maximal value.
    /// @param actual The actual value.
    error MinApprovalsOutOfBounds(uint16 limit, uint16 actual);

    /// @notice Thrown if the address list source is empty
    error InvalidAddressListSource();

    /// @notice Emitted when a proposal is created.
    /// @param proposalId The ID of the proposal.
    /// @param creator  The creator of the proposal.
    /// @param encryptedPayloadURI The IPFS URI where the encrypted proposal data is pinned.
    /// @param destinationActionsHash The hash of the serialized actions that will be executed if the proposal passes.
    event ProposalCreated(
        uint256 indexed proposalId, address indexed creator, bytes encryptedPayloadURI, bytes32 destinationActionsHash
    );

    /// @notice Emitted when a proposal is approved by an approver.
    /// @param proposalId The ID of the proposal.
    /// @param approver The approver casting the approve.
    event Approved(uint256 indexed proposalId, address indexed approver);

    /// @notice Emitted when a proposal passes and is relayed to the destination plugin.
    /// @param proposalId The ID of the proposal.
    event Executed(uint256 indexed proposalId);

    /// @notice Emitted when the plugin settings are set.
    /// @param onlyListed Whether only listed addresses can create a proposal.
    /// @param minApprovals The minimum amount of approvals needed to pass a proposal.
    /// @param addresslistSource The address of the contract holding the address list to use.
    event MultisigSettingsUpdated(bool onlyListed, uint16 indexed minApprovals, Addresslist addresslistSource);

    /// @notice Initializes Release 1, Build 1.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _multisigSettings The multisig settings.
    function initialize(IDAO _dao, MultisigSettings calldata _multisigSettings) external initializer {
        __PluginUUPSUpgradeable_init(_dao);

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
        return _interfaceId == type(IEmergencyMultisig).interfaceId || _interfaceId == type(IMembership).interfaceId
            || super.supportsInterface(_interfaceId);
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
    /// @param _encryptedPayloadURI The URI where the encrypted contents of the proposal can be found.
    /// @param _destinationActionsHash The hash of the serialized actions that will be executed after the proposal passes.
    /// @param _destinationPlugin The address of the plugin to forward the proposal to when it passes.
    /// @param _approveProposal If `true`, the sender will approve the proposal.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata _encryptedPayloadURI,
        bytes32 _destinationActionsHash,
        OptimisticTokenVotingPlugin _destinationPlugin,
        bool _approveProposal
    ) external returns (uint256 proposalId) {
        if (multisigSettings.onlyListed && !multisigSettings.addresslistSource.isListed(msg.sender)) {
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

        proposalId = _createProposalId();

        // Create the proposal
        Proposal storage proposal_ = proposals[proposalId];
        proposal_.encryptedPayloadURI = _encryptedPayloadURI;
        proposal_.destinationPlugin = _destinationPlugin;

        proposal_.parameters.snapshotBlock = snapshotBlock;
        proposal_.parameters.expirationDate = block.timestamp.toUint64() + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD;
        proposal_.parameters.minApprovals = multisigSettings.minApprovals;

        proposal_.destinationActionsHash = _destinationActionsHash;

        emit ProposalCreated({
            proposalId: proposalId,
            creator: msg.sender,
            encryptedPayloadURI: _encryptedPayloadURI,
            destinationActionsHash: _destinationActionsHash
        });

        if (_approveProposal) {
            approve(proposalId);
        }
    }

    /// @inheritdoc IEmergencyMultisig
    function approve(uint256 _proposalId) public {
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

        // Automatic execution is intentionally omitted in order to prevent
        // private actions from accidentally leaving the local computer before being executed
    }

    /// @inheritdoc IEmergencyMultisig
    function canApprove(uint256 _proposalId, address _account) external view returns (bool) {
        return _canApprove(_proposalId, _account);
    }

    /// @inheritdoc IEmergencyMultisig
    function canExecute(uint256 _proposalId) external view returns (bool) {
        return _canExecute(_proposalId);
    }

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return executed Whether the proposal is executed or not.
    /// @return approvals The number of approvals casted.
    /// @return parameters The parameters of the proposal vote.
    /// @return encryptedPayloadURI The URI at which the corresponding encrypted data data can be found.
    /// @return destinationActionsHash The hash of the actions to be executed by the destination plugin after the proposal passes.
    /// @return destinationPlugin The address of the plugin where the proposal will be forwarded to when executed.
    function getProposal(uint256 _proposalId)
        public
        view
        returns (
            bool executed,
            uint16 approvals,
            ProposalParameters memory parameters,
            bytes memory encryptedPayloadURI,
            bytes32 destinationActionsHash,
            OptimisticTokenVotingPlugin destinationPlugin
        )
    {
        Proposal storage proposal_ = proposals[_proposalId];

        executed = proposal_.executed;
        approvals = proposal_.approvals;
        parameters = proposal_.parameters;
        encryptedPayloadURI = proposal_.encryptedPayloadURI;
        destinationActionsHash = proposal_.destinationActionsHash;
        destinationPlugin = proposal_.destinationPlugin;
    }

    /// @inheritdoc IEmergencyMultisig
    function hasApproved(uint256 _proposalId, address _account) public view returns (bool) {
        return proposals[_proposalId].approvers[_account];
    }

    /// @inheritdoc IEmergencyMultisig
    function execute(uint256 _proposalId, IDAO.Action[] calldata _actions) public {
        if (!_canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }

        if (proposals[_proposalId].destinationActionsHash != hashActions(_actions)) {
            // This check is intentionally not part of canExecute() in order to prevent
            // the private actions from ever leaving the local computer before being executed
            revert InvalidActions(_proposalId);
        }

        _execute(_proposalId, _actions);
    }

    /// @notice Computes the hash of the given list of actions
    /// @param _actions the list of actions
    /// @return actionsHash The keccak of the payload
    function hashActions(IDAO.Action[] calldata _actions) public pure returns (bytes32 actionsHash) {
        actionsHash = keccak256(abi.encode(_actions));
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        return multisigSettings.addresslistSource.isListed(_account);
    }

    /// @notice Internal function to execute a vote. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    function _execute(uint256 _proposalId, IDAO.Action[] calldata _actions) internal {
        Proposal storage proposal_ = proposals[_proposalId];

        proposal_.executed = true;
        emit Executed(_proposalId);

        proposal_.destinationPlugin.createProposal(
            proposal_.encryptedPayloadURI,
            _actions,
            0, // allowFailureMap, no single action may fail
            0 // no duration, immediate executioon
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

        if (!multisigSettings.addresslistSource.isListedAtBlock(_account, proposal_.parameters.snapshotBlock)) {
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
        if (!IERC165(address(_multisigSettings.addresslistSource)).supportsInterface(type(Addresslist).interfaceId)) {
            revert InvalidAddressListSource();
        } else if (_multisigSettings.minApprovals < 1) {
            revert MinApprovalsOutOfBounds({limit: 1, actual: _multisigSettings.minApprovals});
        }

        uint16 addresslistLength_ = uint16(_multisigSettings.addresslistSource.addresslistLength());

        if (_multisigSettings.minApprovals > addresslistLength_) {
            revert MinApprovalsOutOfBounds({limit: addresslistLength_, actual: _multisigSettings.minApprovals});
        }

        multisigSettings = _multisigSettings;
        lastMultisigSettingsChange = block.number.toUint64();

        emit MultisigSettingsUpdated({
            onlyListed: _multisigSettings.onlyListed,
            minApprovals: _multisigSettings.minApprovals,
            addresslistSource: _multisigSettings.addresslistSource
        });
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[47] private __gap;
}
