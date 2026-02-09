// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBridge} from "../interfaces/IBridge.sol";
import {IMessageInvocable} from "../interfaces/IMessageInvocable.sol";
import {IL2VetoReceiver} from "../interfaces/IL2VetoReceiver.sol";
import {IOptimisticTokenVoting} from "../interfaces/IOptimisticTokenVoting.sol";
import {OptimisticTokenVotingPlugin} from "../OptimisticTokenVotingPlugin.sol";

/// @title L2VetoReceiver
/// @notice L1 contract that receives aggregated L2 veto tallies via Taiko Bridge
/// @dev Implements IMessageInvocable for bridge callbacks.
///
/// Push Model:
/// 1. Receives L2 veto tallies from the bridge
/// 2. Validates the proposalId against the plugin's proposal data
/// 3. Stores the tally locally (for staleness protection)
/// 4. Immediately pushes to the plugin via receiveL2Vetoes()
///
/// Security model:
/// 1. Only accepts calls from the Taiko Bridge contract
/// 2. Verifies bridge context shows message from trusted L2 aggregator
/// 3. Verifies source chain ID matches expected L2
/// 4. Validates proposalId contains correct timestamps from the plugin
/// 5. Allows partial aggregation (later messages replace earlier tallies)
///
/// Deployment:
/// 1. Deploy L2VetoReceiver on L1 (trustedL2Aggregator can be zero initially)
/// 2. Deploy L2VetoAggregator on L2
/// 3. Call setTrustedL2Aggregator() with L2VetoAggregator address
/// 4. Call setL1Receiver() on L2VetoAggregator with this contract's address
/// 5. Call renounceOwnership() on both contracts to lock configuration
contract L2VetoReceiver is IL2VetoReceiver, IMessageInvocable, Ownable {
    // =========================================================================
    // IMMUTABLES
    // =========================================================================

    /// @notice The Taiko Bridge contract address
    address public immutable override bridge;

    /// @notice The expected L2 chain ID for validation
    uint64 public immutable override l2ChainId;

    /// @notice The voting plugin address
    address public immutable override votingPlugin;

    // =========================================================================
    // STORAGE
    // =========================================================================

    /// @notice The trusted L2VetoAggregator address on L2
    address public override trustedL2Aggregator;

    /// @notice Mapping of proposalId => L2 veto tally
    mapping(uint256 => uint256) private _l2VetoTallies;

    /// @notice Mapping of proposalId => dispatch timestamp
    mapping(uint256 => uint256) private _l2DispatchTimestamps;

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Thrown when proposalId timestamps don't match the plugin's proposal
    error InvalidProposalId();

    /// @notice Thrown when there are no votes to submit
    error NoVotesToSubmit();

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Constructs the L2VetoReceiver
    /// @dev The deployer becomes the owner. After configuring trustedL2Aggregator,
    ///      call renounceOwnership() to lock the configuration.
    /// @param _bridge The Taiko Bridge address on L1
    /// @param _l2ChainId The expected L2 chain ID
    /// @param _votingPlugin The OptimisticTokenVotingPlugin address
    constructor(address _bridge, uint64 _l2ChainId, address _votingPlugin) {
        if (_bridge == address(0)) revert InvalidAddress();
        if (_l2ChainId == 0) revert InvalidAddress();
        if (_votingPlugin == address(0)) revert InvalidAddress();

        bridge = _bridge;
        l2ChainId = _l2ChainId;
        votingPlugin = _votingPlugin;
    }

    // =========================================================================
    // BRIDGE CALLBACK
    // =========================================================================

    /// @notice Called by the Taiko Bridge to deliver L2 veto tallies
    /// @dev Implements IMessageInvocable interface
    /// @param _data ABI-encoded (uint256 proposalId, uint256 vetoTally, uint256 dispatchedAt)
    function onMessageInvocation(bytes calldata _data) external payable override {
        // Security check 1: Only bridge can call
        if (msg.sender != bridge) revert CallerNotBridge();

        // Security check 2: Verify message is from trusted L2 aggregator
        IBridge.Context memory ctx = IBridge(bridge).context();
        if (ctx.from != trustedL2Aggregator) revert UntrustedL2Sender();

        // Security check 3: Verify source chain ID
        if (ctx.srcChainId != l2ChainId) revert InvalidSourceChain();

        // Decode the veto data
        (uint256 proposalId, uint256 vetoTally, uint256 dispatchedAt) = abi.decode(_data, (uint256, uint256, uint256));

        // Security check 4: Validate proposalId against plugin's proposal data
        if (!isProposalIdValid(proposalId)) revert InvalidProposalId();

        // Only accept if newer than existing (prevents stale message replay)
        uint256 existingTimestamp = _l2DispatchTimestamps[proposalId];
        if (dispatchedAt <= existingTimestamp) revert StaleVetoMessage();

        // Store the L2 veto data (replaces previous tally for partial aggregation)
        _l2VetoTallies[proposalId] = vetoTally;
        _l2DispatchTimestamps[proposalId] = dispatchedAt;

        emit L2VetosReceived(proposalId, vetoTally, dispatchedAt);

        // Push to the plugin - if this fails, submitL2Vetoes() can be called later
        try this.submitL2Vetoes(proposalId) {}
        catch (bytes memory revertData) {
            emit SubmitVetoFailed(proposalId, vetoTally, revertData);
        }
    }

    // =========================================================================
    // PUBLIC FUNCTIONS
    // =========================================================================

    /// @notice Submits stored L2 vetoes to the voting plugin
    /// @dev Can be called manually if the automatic submission in onMessageInvocation fails
    /// @param _proposalId The proposal ID to submit vetoes for
    function submitL2Vetoes(uint256 _proposalId) external {
        uint256 vetoTally = _l2VetoTallies[_proposalId];

        // No-op if no vetoes stored (also prevents repeated success events)
        if (_l2DispatchTimestamps[_proposalId] == 0) revert NoVotesToSubmit();

        // Call the plugin to receive the L2 vetoes
        IOptimisticTokenVoting(votingPlugin).receiveL2Vetoes(_proposalId, vetoTally);

        emit SubmitVetoSuccess(_proposalId, vetoTally);
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Validates that a proposalId's encoded timestamps match the plugin's proposal
    /// @param _proposalId The proposal ID to validate
    /// @return True if the proposalId is valid
    function isProposalIdValid(uint256 _proposalId) public view returns (bool) {
        // Parse the encoded timestamps from the proposalId
        (, uint64 startDate, uint64 endDate, uint64 snapshotTimestamp) =
            OptimisticTokenVotingPlugin(votingPlugin).parseProposalId(_proposalId);

        // Get the actual proposal parameters from the plugin
        (,, IOptimisticTokenVoting.ProposalParameters memory params,,,,) =
            IOptimisticTokenVoting(votingPlugin).getProposal(_proposalId);

        // Proposal must exist (a real proposal always has non-zero snapshotTimestamp)
        if (params.snapshotTimestamp == 0) return false;

        // Validate timestamps match (proposal exists and hasn't been tampered with)
        return params.snapshotTimestamp == snapshotTimestamp && params.vetoStartDate == startDate
            && params.vetoEndDate == endDate;
    }

    /// @inheritdoc IL2VetoReceiver
    function getL2VetoTally(uint256 _proposalId) external view override returns (uint256) {
        return _l2VetoTallies[_proposalId];
    }

    /// @inheritdoc IL2VetoReceiver
    function getL2DispatchTimestamp(uint256 _proposalId) external view override returns (uint256) {
        return _l2DispatchTimestamps[_proposalId];
    }

    /// @inheritdoc IL2VetoReceiver
    function hasReceivedL2Vetoes(uint256 _proposalId) external view override returns (bool) {
        return _l2DispatchTimestamps[_proposalId] != 0;
    }

    // =========================================================================
    // ADMIN
    // =========================================================================

    /// @inheritdoc IL2VetoReceiver
    function setTrustedL2Aggregator(address _trustedL2Aggregator) external override onlyOwner {
        if (_trustedL2Aggregator == address(0)) revert InvalidAddress();

        address oldAggregator = trustedL2Aggregator;
        trustedL2Aggregator = _trustedL2Aggregator;

        emit TrustedL2AggregatorUpdated(oldAggregator, _trustedL2Aggregator);
    }
}
