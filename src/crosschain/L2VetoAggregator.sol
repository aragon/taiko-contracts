// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IBridge} from "../interfaces/IBridge.sol";
import {IMessageInvocable} from "../interfaces/IMessageInvocable.sol";
import {IL2VetoAggregator} from "../interfaces/IL2VetoAggregator.sol";

/// @title L2VetoAggregator
/// @notice L2 contract that allows L2 token holders to veto L1 proposals.
///         Validates proposals by decoding the proposalId (which embeds timestamps),
///         tracks veto votes using the L2 bridged voting token, and dispatches
///         aggregated tallies to L1 via the Taiko Bridge.
///
/// @dev The L2 contract does NOT mirror L1 state. It decodes the proposalId to determine
///      timing — no oracle or event tracking is needed.
///
/// ProposalId encoding (from L1):
///   bits 192-255: snapshotTimestamp
///   bits 128-191: startDate
///   bits 64-127:  endDate
///   bits 0-63:    counter
///
/// Flow:
///   1. L2 voter calls veto(proposalId) with a proposalId from L1
///   2. Contract decodes startDate/endDate, checks startDate <= now < endDate
///   3. Reads voter power via votingToken.getPastVotes(voter, snapshotTimestamp)
///   4. Stores per-proposal tally, marks voter as having vetoed
///   5. Anyone calls dispatch(proposalId) to bridge (proposalId, vetoTally, block.timestamp) to L1
///
/// Deployment:
///   1. Deploy L2VetoAggregator on L2 (l1Receiver can be zero initially)
///   2. Deploy L2VetoReceiver on L1
///   3. Call setL1Receiver() with L2VetoReceiver address
///   4. Call setTrustedL2Aggregator() on L2VetoReceiver with this contract's address
///   5. Call renounceOwnership() on both contracts to lock configuration
contract L2VetoAggregator is IL2VetoAggregator, Ownable {
    // =========================================================================
    // IMMUTABLES
    // =========================================================================

    /// @notice The Taiko Bridge contract address on L2
    address public immutable override bridge;

    /// @notice The L1 chain ID for bridge message routing
    uint64 public immutable override l1ChainId;

    /// @notice The L2 voting token (bridged from L1) with ERC20Votes support
    IVotesUpgradeable public immutable override votingToken;

    // =========================================================================
    // STORAGE
    // =========================================================================

    /// @notice The L2VetoReceiver address on L1 (owner-settable)
    address public override l1Receiver;

    /// @notice Mapping of proposalId => total veto voting power
    mapping(uint256 => uint256) private _tallies;

    /// @notice Mapping of proposalId => voter => has vetoed
    mapping(uint256 => mapping(address => bool)) private _hasVetoed;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Constructs the L2VetoAggregator
    /// @dev The deployer becomes the owner. After configuring l1Receiver,
    ///      call renounceOwnership() to lock the configuration.
    /// @param _bridge The Taiko Bridge address on L2
    /// @param _l1ChainId The L1 chain ID
    /// @param _votingToken The L2 bridged voting token with ERC20Votes support
    constructor(address _bridge, uint64 _l1ChainId, address _votingToken) {
        if (_bridge == address(0)) revert InvalidAddress();
        if (_l1ChainId == 0) revert InvalidAddress();
        if (_votingToken == address(0)) revert InvalidAddress();

        bridge = _bridge;
        l1ChainId = _l1ChainId;
        votingToken = IVotesUpgradeable(_votingToken);
    }

    // =========================================================================
    // CORE FUNCTIONS
    // =========================================================================

    /// @inheritdoc IL2VetoAggregator
    function veto(uint256 proposalId) external override {
        address _voter = _msgSender();

        if (!canVeto(proposalId, _voter)) {
            revert ProposalVetoingForbidden(proposalId, _voter);
        }

        (uint64 snapshotTimestamp,,) = _decodeTimestamps(proposalId);
        uint256 votingPower = votingToken.getPastVotes(_voter, snapshotTimestamp);

        // Update state
        _tallies[proposalId] += votingPower;
        _hasVetoed[proposalId][_voter] = true;

        emit VetoCast(proposalId, _voter, votingPower);
    }

    function canVeto(uint256 proposalId, address voter) public view returns (bool) {
        // Decode proposal timing from the proposalId
        (uint64 snapshotTimestamp, uint64 startDate, uint64 endDate) = _decodeTimestamps(proposalId);

        // Check veto period is open
        if (snapshotTimestamp == 0 || block.timestamp < startDate || block.timestamp >= endDate) {
            return false;
        }

        // Check voter hasn't already vetoed
        if (_hasVetoed[proposalId][voter]) {
            return false;
        }

        // Read voting power at the snapshot timestamp
        uint256 votingPower = votingToken.getPastVotes(voter, snapshotTimestamp);
        if (votingPower == 0) return false;

        return true;
    }

    /// @inheritdoc IL2VetoAggregator
    function dispatch(uint256 proposalId) external payable override {
        if (l1Receiver == address(0)) revert NoL1Receiver();

        uint256 vetoTally = _tallies[proposalId];

        // Encode the veto data for L1
        bytes memory vetoData = abi.encode(proposalId, vetoTally, block.timestamp);

        // Encode the bridge message calldata targeting onMessageInvocation
        bytes memory msgData = abi.encodeCall(IMessageInvocable.onMessageInvocation, (vetoData));

        // Build the bridge message
        IBridge.Message memory message = IBridge.Message({
            id: 0, // Assigned by bridge
            fee: uint64(msg.value), // Relayer fee from caller's ETH
            gasLimit: 1_000_000,
            from: address(0), // Assigned by bridge
            srcChainId: 0, // Assigned by bridge
            srcOwner: msg.sender,
            destChainId: l1ChainId,
            destOwner: msg.sender,
            to: l1Receiver,
            value: 0,
            data: msgData
        });

        // Send via bridge
        (bytes32 msgHash,) = IBridge(bridge).sendMessage{value: msg.value}(message);

        emit VetoDispatched(proposalId, vetoTally, msgHash);
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @inheritdoc IL2VetoAggregator
    function getVetoTally(uint256 proposalId) external view override returns (uint256) {
        return _tallies[proposalId];
    }

    /// @inheritdoc IL2VetoAggregator
    function hasVetoed(uint256 proposalId, address voter) external view override returns (bool) {
        return _hasVetoed[proposalId][voter];
    }

    /// @inheritdoc IL2VetoAggregator
    function isProposalOpen(uint256 proposalId) external view override returns (bool) {
        (, uint64 startDate, uint64 endDate) = _decodeTimestamps(proposalId);
        return block.timestamp >= startDate && block.timestamp < endDate;
    }

    /// @notice Splits the components behind the given proposal ID
    /// @param proposalId The ID to split
    /// @return counter The autoincremented counter
    /// @return startDate The proposal veto start timestamp
    /// @return endDate The proposal veto end timestamp
    /// @return snapshotTimestamp The voting power snapshot timestamp
    function parseProposalId(uint256 proposalId)
        public
        pure
        returns (uint64 counter, uint64 startDate, uint64 endDate, uint64 snapshotTimestamp)
    {
        counter = uint64(proposalId & type(uint64).max);
        endDate = uint64(proposalId >> 64) & type(uint64).max;
        startDate = uint64(proposalId >> 128) & type(uint64).max;
        snapshotTimestamp = uint64(proposalId >> 192);
    }

    // =========================================================================
    // ADMIN
    // =========================================================================

    /// @inheritdoc IL2VetoAggregator
    function setL1Receiver(address newReceiver) external override onlyOwner {
        if (newReceiver == address(0)) revert InvalidAddress();

        address oldReceiver = l1Receiver;
        l1Receiver = newReceiver;

        emit L1ReceiverUpdated(oldReceiver, newReceiver);
    }

    // =========================================================================
    // INTERNAL
    // =========================================================================

    /// @dev Extracts snapshotTimestamp, startDate, and endDate from the encoded proposalId
    function _decodeTimestamps(uint256 proposalId)
        internal
        pure
        returns (uint64 snapshotTimestamp, uint64 startDate, uint64 endDate)
    {
        snapshotTimestamp = uint64(proposalId >> 192);
        startDate = uint64(proposalId >> 128) & type(uint64).max;
        endDate = uint64(proposalId >> 64) & type(uint64).max;
    }
}
