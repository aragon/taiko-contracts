// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title IL2VetoReceiver
/// @notice Interface for the L1 contract that receives L2 veto tallies via Taiko Bridge
/// @dev Bridge and L2 chain ID are immutable. Trusted aggregator requires SET_TRUSTED_L2_AGGREGATOR_PERMISSION.
///
/// Push Model:
/// 1. Receiver stores the L2 veto tally for staleness protection
/// 2. Receiver immediately calls plugin.receiveL2Vetoes() to submit
/// 3. If submission fails, submitL2Vetoes() can be called later
interface IL2VetoReceiver {
    // =========================================================================
    // EVENTS
    // =========================================================================

    /// @notice Emitted when L2 vetoes are received and stored
    /// @param proposalId The proposal ID on L1
    /// @param vetoTally The total L2 veto voting power
    /// @param dispatchedAt The timestamp when vetoes were dispatched from L2
    event L2VetoTallyBridged(uint256 indexed proposalId, uint256 vetoTally, uint256 dispatchedAt);

    /// @notice Emitted when L2 vetoes are successfully submitted to the voting plugin
    /// @param proposalId The proposal ID
    /// @param vetoTally The veto tally submitted
    event SubmitVetoSuccess(uint256 indexed proposalId, uint256 vetoTally);

    /// @notice Emitted when L2 veto submission to the plugin fails
    /// @param proposalId The proposal ID
    /// @param vetoTally The veto tally that failed to submit
    /// @param revertData The revert data from the failed call
    event SubmitVetoFailed(uint256 indexed proposalId, uint256 vetoTally, bytes revertData);

    /// @notice Emitted when the trusted L2 aggregator is updated
    /// @param oldAggregator The previous aggregator address
    /// @param newAggregator The new aggregator address
    event TrustedL2AggregatorUpdated(address oldAggregator, address newAggregator);

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Thrown when caller is not the Taiko Bridge
    error CallerNotBridge();

    /// @notice Thrown when message sender (context.from) is not the trusted L2 aggregator
    error UntrustedL2Sender();

    /// @notice Thrown when source chain ID doesn't match expected L2 chain
    error InvalidSourceChain();

    /// @notice Thrown when message timestamp is not newer than existing tally
    error StaleVetoMessage();

    /// @notice Thrown when setting zero address in constructor
    error InvalidAddress();

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Returns the L2 veto tally for a proposal
    /// @param proposalId The proposal ID on L1
    /// @return The total L2 veto voting power (0 if not received)
    function getL2VetoTally(uint256 proposalId) external view returns (uint256);

    /// @notice Returns when the L2 vetoes were dispatched
    /// @param proposalId The proposal ID on L1
    /// @return The dispatch timestamp (0 if not received)
    function getL2DispatchTimestamp(uint256 proposalId) external view returns (uint256);

    /// @notice Checks if L2 vetoes have been received for a proposal
    /// @param proposalId The proposal ID on L1
    /// @return True if vetoes have been received
    function hasReceivedL2Vetoes(uint256 proposalId) external view returns (bool);

    /// @notice Returns the voting plugin address
    /// @return The address of the OptimisticTokenVotingPlugin
    function votingPlugin() external view returns (address);

    /// @notice Returns the trusted L2 aggregator address
    /// @return The address of the L2VetoAggregator contract on L2
    function trustedL2Aggregator() external view returns (address);

    /// @notice Returns the Taiko Bridge address (immutable)
    /// @return The address of the Taiko Bridge contract on L1
    function bridge() external view returns (address);

    /// @notice Returns the expected L2 chain ID (immutable)
    /// @return The chain ID of the L2 network
    function l2ChainId() external view returns (uint64);

    // =========================================================================
    // ADMIN
    // =========================================================================

    /// @notice Sets the trusted L2 aggregator address
    /// @dev Requires SET_TRUSTED_L2_AGGREGATOR_PERMISSION
    /// @param newAggregator The new L2VetoAggregator address on L2
    function setTrustedL2Aggregator(address newAggregator) external;
}
