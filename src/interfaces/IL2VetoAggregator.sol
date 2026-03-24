// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

/// @title IL2VetoAggregator
/// @notice Interface for the L2 contract that aggregates veto votes from L2 token holders
///         and dispatches tallies to L1 via the Taiko Bridge.
interface IL2VetoAggregator {
    // =========================================================================
    // EVENTS
    // =========================================================================

    /// @notice Emitted when a voter casts a veto on a proposal
    /// @param proposalId The L1 proposal ID
    /// @param voter The address that vetoed
    /// @param votingPower The voting power behind this veto
    event VetoCast(uint256 indexed proposalId, address indexed voter, uint256 votingPower);

    /// @notice Emitted when a veto tally is dispatched to L1 via the bridge
    /// @param proposalId The L1 proposal ID
    /// @param vetoTally The total veto power dispatched
    /// @param msgHash The bridge message hash
    event VetoDispatched(uint256 indexed proposalId, uint256 vetoTally, bytes32 msgHash);

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Thrown when a proposal's veto period is not currently open
    error ProposalVetoingForbidden(uint256 proposalId, address voter);

    /// @notice Thrown when setting a zero address where one is not allowed
    error InvalidAddress();

    /// @notice Thrown when dispatching with zero veto tally (nothing to send)
    error NothingToDispatch();

    // =========================================================================
    // CORE FUNCTIONS
    // =========================================================================

    /// @notice Casts a veto on an L1 proposal using the caller's L2 voting power
    /// @param proposalId The L1 proposal ID (encodes snapshot, start, end, counter)
    function veto(uint256 proposalId) external;

    /// @notice Dispatches the aggregated veto tally to L1 via the Taiko Bridge
    /// @param proposalId The L1 proposal ID
    function dispatch(uint256 proposalId) external payable;

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Returns the current veto tally for a proposal
    /// @param proposalId The L1 proposal ID
    /// @return The total veto voting power accumulated
    function getVetoTally(uint256 proposalId) external view returns (uint256);

    /// @notice Checks if an address has already vetoed a proposal
    /// @param proposalId The L1 proposal ID
    /// @param voter The address to check
    /// @return True if the voter has already vetoed
    function hasVetoed(uint256 proposalId, address voter) external view returns (bool);

    /// @notice Checks if a proposal's veto period is currently open
    /// @param proposalId The L1 proposal ID
    /// @return True if startDate <= block.timestamp < endDate
    function isProposalOpen(uint256 proposalId) external view returns (bool);

    /// @notice Returns the Taiko Bridge address (immutable)
    /// @return The bridge contract address
    function bridge() external view returns (address);

    /// @notice Returns the L1 chain ID (immutable)
    /// @return The L1 chain ID
    function l1ChainId() external view returns (uint64);

    /// @notice Returns the L1 receiver address
    /// @return The L2VetoReceiver contract address on L1
    function l1Receiver() external view returns (address);

    /// @notice Returns the voting token address (immutable)
    /// @return The IVotesUpgradeable token used for voting power
    function votingToken() external view returns (IVotesUpgradeable);

}
