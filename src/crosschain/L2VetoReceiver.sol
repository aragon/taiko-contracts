// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {IBridge} from "../interfaces/IBridge.sol";
import {IMessageInvocable} from "../interfaces/IMessageInvocable.sol";
import {IL2VetoReceiver} from "../interfaces/IL2VetoReceiver.sol";

/// @title L2VetoReceiver
/// @notice L1 contract that receives aggregated L2 veto tallies via Taiko Bridge
/// @dev Implements IMessageInvocable for bridge callbacks. All configuration is immutable.
///
/// Security model:
/// 1. Only accepts calls from the Taiko Bridge contract
/// 2. Verifies bridge context shows message from trusted L2 aggregator
/// 3. Verifies source chain ID matches expected L2
/// 4. Allows partial aggregation (later messages replace earlier tallies)
///
/// Configuration changes:
/// - To change the trusted L2 aggregator, deploy a new L2VetoReceiver
/// - Update the OptimisticTokenVotingPlugin via setL2VetoReceiver()
/// - This keeps the receiver simple and reduces attack surface
contract L2VetoReceiver is IL2VetoReceiver, IMessageInvocable {
    // =========================================================================
    // IMMUTABLES
    // =========================================================================

    /// @notice The Taiko Bridge contract address
    address public immutable override bridge;

    /// @notice The trusted L2VetoAggregator address on L2
    address public immutable override trustedL2Aggregator;

    /// @notice The expected L2 chain ID for validation
    uint64 public immutable override l2ChainId;

    // =========================================================================
    // STORAGE
    // =========================================================================

    /// @notice Mapping of proposalRef => L2 veto tally
    mapping(bytes32 => uint256) private _l2VetoTallies;

    /// @notice Mapping of proposalRef => dispatch timestamp
    mapping(bytes32 => uint256) private _l2DispatchTimestamps;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Constructs the L2VetoReceiver with immutable configuration
    /// @param _bridge The Taiko Bridge address on L1
    /// @param _trustedL2Aggregator The trusted L2VetoAggregator address on L2
    /// @param _l2ChainId The expected L2 chain ID
    constructor(address _bridge, address _trustedL2Aggregator, uint64 _l2ChainId) {
        if (_bridge == address(0)) revert InvalidAddress();
        if (_trustedL2Aggregator == address(0)) revert InvalidAddress();
        if (_l2ChainId == 0) revert InvalidAddress();

        bridge = _bridge;
        trustedL2Aggregator = _trustedL2Aggregator;
        l2ChainId = _l2ChainId;
    }

    // =========================================================================
    // BRIDGE CALLBACK
    // =========================================================================

    /// @notice Called by the Taiko Bridge to deliver L2 veto tallies
    /// @dev Implements IMessageInvocable interface
    /// @param _data ABI-encoded (bytes32 proposalRef, uint256 vetoTally, uint256 dispatchedAt)
    function onMessageInvocation(bytes calldata _data) external payable override {
        // Security check 1: Only bridge can call
        if (msg.sender != bridge) revert CallerNotBridge();

        // Security check 2: Verify message is from trusted L2 aggregator
        IBridge.Context memory ctx = IBridge(bridge).context();
        if (ctx.from != trustedL2Aggregator) revert UntrustedL2Sender();

        // Security check 3: Verify source chain ID
        if (ctx.srcChainId != l2ChainId) revert InvalidSourceChain();

        // Decode the veto data
        (bytes32 proposalRef, uint256 vetoTally, uint256 dispatchedAt) =
            abi.decode(_data, (bytes32, uint256, uint256));

        // Only accept if newer than existing (prevents stale message replay)
        uint256 existingTimestamp = _l2DispatchTimestamps[proposalRef];
        if (dispatchedAt <= existingTimestamp) revert StaleVetoMessage();

        // Store the L2 veto data (replaces previous tally for partial aggregation)
        _l2VetoTallies[proposalRef] = vetoTally;
        _l2DispatchTimestamps[proposalRef] = dispatchedAt;

        emit L2VetosReceived(proposalRef, vetoTally, dispatchedAt);
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @inheritdoc IL2VetoReceiver
    function getL2VetoTally(bytes32 _proposalRef) external view override returns (uint256) {
        return _l2VetoTallies[_proposalRef];
    }

    /// @inheritdoc IL2VetoReceiver
    function getL2DispatchTimestamp(bytes32 _proposalRef) external view override returns (uint256) {
        return _l2DispatchTimestamps[_proposalRef];
    }

    /// @inheritdoc IL2VetoReceiver
    function hasReceivedL2Vetoes(bytes32 _proposalRef) external view override returns (bool) {
        return _l2DispatchTimestamps[_proposalRef] != 0;
    }
}
