// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Adapted interface for querying Taiko rollup status on L1.
/// Supports the Shasta inbox (getCoreState) which replaced Pacaya's getLastVerifiedBlock.
interface ITaikoL1 {
    struct CoreState {
        uint48 nextProposalId;
        uint48 lastProposalBlockId;
        uint48 lastFinalizedProposalId;
        uint48 lastFinalizedTimestamp;
        uint48 lastCheckpointTimestamp;
        bytes32 lastFinalizedBlockHash;
    }

    /// @notice Returns true if the contract is paused, and false otherwise.
    function paused() external view returns (bool);

    /// @notice Returns the core state of the inbox including the last finalized timestamp.
    function getCoreState() external view returns (CoreState memory);
}
