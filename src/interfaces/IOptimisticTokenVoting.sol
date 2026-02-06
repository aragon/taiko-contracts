// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

/// @title IOptimisticTokenVoting
/// @author Aragon Association - 2022-2023
/// @notice The interface of an optimistic governance plugin.
interface IOptimisticTokenVoting {
    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param vetoStartDate The start date of the proposal veto.
    /// @param vetoEndDate The end date of the proposal vote
    /// @param snapshotTimestamp The timestamp prior to the proposal creation.
    /// @param minVetoRatio The minimum veto ratio needed to defeat the proposal.
    /// @param unavailableL2 True if the L2 was unavailable when the proposal was created.
    struct ProposalParameters {
        uint64 vetoStartDate;
        uint64 vetoEndDate;
        uint64 snapshotTimestamp;
        uint32 minVetoRatio;
        bool unavailableL2;
    }

    /// @notice getter function for the voting token.
    /// @dev public function also useful for registering interfaceId and for distinguishing from majority voting interface.
    /// @return The token used for voting.
    function votingToken() external view returns (IVotesUpgradeable);

    /// @notice Returns the total voting power checkpointed for a specific timestamp.
    /// @param _timestamp The target timestamp.
    /// @return The total voting power.
    function totalVotingPower(uint256 _timestamp) external view returns (uint256);

    /// @notice Returns the total voting power bridged to the L2 at the given timestamp.
    /// @dev This assumes that the Taiko Bridge is delegating to itself.
    /// @param _timestamp The target timestamp.
    /// @return The total bridged voting power.
    function bridgedVotingPower(uint256 _timestamp) external view returns (uint256);

    /// @notice Returns the effective voting power that can vote at the given timestamp.
    /// @dev This assumes that the Taiko Bridge is delegating to itself.
    /// @param _timestamp The target timestamp.
    /// @param _isL2Available Whether the L2 can be part of the voting power or not.
    /// @return The total bridged voting power.
    function effectiveVotingPower(uint256 _timestamp, bool _isL2Available) external view returns (uint256);

    /// @notice Returns true is the L2 is currently available.
    function isL2Available() external view returns (bool);

    /// @notice Returns the veto ratio parameter stored in the optimistic governance settings.
    /// @return The veto ratio parameter.
    function minVetoRatio() external view returns (uint32);

    /// @notice Creates a new optimistic proposal.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap Allows proposal to succeed even if an action reverts. Uses bitmap representation. If the bit at index `x` is 1, the tx succeeds even if the action at `x` failed. Passing 0 will be treated as atomic execution.
    /// @param _duration The amount of seconds to allow for token holders to veto. NOTE: If the supplied value is zero, the proposal will be treated as an emergency one.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _duration
    ) external returns (uint256 proposalId);

    /// @notice Checks if an account can participate on an optimistic proposal. This can be because the proposal
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the voter doesn't have voting power.
    /// @param _proposalId The proposal Id.
    /// @param _account The account address to be checked.
    /// @return Returns true if the account is allowed to veto.
    /// @dev The function assumes that the queried proposal exists.
    function canVeto(uint256 _proposalId, address _account) external view returns (bool);

    /// @notice Registers the veto for the given proposal.
    /// @param _proposalId The ID of the proposal.
    function veto(uint256 _proposalId) external;

    /// @notice Returns whether the account has voted for the proposal.  Note, that this does not check if the account has vetoing power.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account address to be checked.
    /// @return The whether the given account has vetoed the given proposal.
    function hasVetoed(uint256 _proposalId, address _account) external view returns (bool);

    /// @notice Checks if the total votes against a proposal is greater than the veto threshold.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the total veto power against the proposal is greater or equal than the threshold and `false` otherwise.
    function isMinVetoRatioReached(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if a proposal can be executed.
    /// @param _proposalId The ID of the proposal to be checked.
    /// @return True if the proposal can be executed, false otherwise.
    function canExecute(uint256 _proposalId) external view returns (bool);

    /// @notice Executes a proposal.
    /// @param _proposalId The ID of the proposal to be executed.
    function execute(uint256 _proposalId) external;

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal vote.
    /// @return vetoTally The current voting power used to veto the proposal.
    /// @return metadataURI The IPFS URI at which the metadata is pinned.
    /// @return actions The actions to be executed in the associated DAO after the proposal has passed.
    /// @return allowFailureMap The bit map representations of which actions are allowed to revert so tx still succeeds.
    function getProposal(uint256 _proposalId)
        external
        view
        returns (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 vetoTally,
            bytes memory metadataURI,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        );

    /// @notice Receives aggregated L2 vetoes from the L2VetoReceiver.
    /// @param _proposalId The ID of the proposal.
    /// @param _vetoTally The total L2 veto voting power to add.
    function receiveL2Vetoes(uint256 _proposalId, uint256 _vetoTally) external;
}
