// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title IL2VetoReceiver
/// @notice Interface for the L1 contract that receives L2 veto tallies via Taiko Bridge
/// @dev Configuration is immutable. To change trusted aggregator, deploy new receiver
///      and update the plugin via setL2VetoReceiver().
interface IL2VetoReceiver {
    // =========================================================================
    // EVENTS
    // =========================================================================

    /// @notice Emitted when L2 vetoes are received and stored
    /// @param proposalRef The unique proposal reference (hash of chainId + plugin + proposalId)
    /// @param vetoTally The total L2 veto voting power
    /// @param dispatchedAt The timestamp when vetoes were dispatched from L2
    event L2VetosReceived(bytes32 indexed proposalRef, uint256 vetoTally, uint256 dispatchedAt);

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
    /// @param proposalRef The unique proposal reference
    /// @return The total L2 veto voting power (0 if not received)
    function getL2VetoTally(bytes32 proposalRef) external view returns (uint256);

    /// @notice Returns when the L2 vetoes were dispatched
    /// @param proposalRef The unique proposal reference
    /// @return The dispatch timestamp (0 if not received)
    function getL2DispatchTimestamp(bytes32 proposalRef) external view returns (uint256);

    /// @notice Checks if L2 vetoes have been received for a proposal
    /// @param proposalRef The unique proposal reference
    /// @return True if vetoes have been received
    function hasReceivedL2Vetoes(bytes32 proposalRef) external view returns (bool);

    /// @notice Returns the trusted L2 aggregator address (immutable)
    /// @return The address of the L2VetoAggregator contract on L2
    function trustedL2Aggregator() external view returns (address);

    /// @notice Returns the Taiko Bridge address (immutable)
    /// @return The address of the Taiko Bridge contract on L1
    function bridge() external view returns (address);

    /// @notice Returns the expected L2 chain ID (immutable)
    /// @return The chain ID of the L2 network
    function l2ChainId() external view returns (uint64);
}
