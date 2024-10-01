// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Manual copy of lib/taiko-mono/packages/protocol/contracts/L1/TaikoL1.sol and its dependent structs
/// This is in order to overcome the conflicting compiler versions between 0.8.17 (OSx) and 0.8.24 (Taiko)
abstract contract TaikoL1 {
    TaikoData.State public state;

    /// @notice Returns true if the contract is paused, and false otherwise.
    /// @return true if paused, false otherwise.
    function paused() public view virtual returns (bool);

    /// @notice Gets the state variables of the TaikoL1 contract.
    /// @dev This method can be deleted once node/client stops using it.
    /// @return State variables stored at SlotA.
    /// @return State variables stored at SlotB.
    function getStateVariables() external view virtual returns (TaikoData.SlotA memory, TaikoData.SlotB memory);

    /// @notice Gets the details of a block.
    /// @param _blockId Index of the block.
    /// @return blk_ The block.
    function getBlockV2(uint64 _blockId) external view virtual returns (TaikoData.BlockV2 memory);
}

library TaikoData {
    /// @dev Struct containing data required for verifying a block.
    /// 3 slots used.
    struct BlockV2 {
        bytes32 metaHash; // slot 1
        address assignedProver; // slot 2
        uint96 livenessBond;
        uint64 blockId; // slot 3
        // Before the fork, this field is the L1 timestamp when this block is proposed.
        // After the fork, this is the timestamp of the L2 block.
        // In a later fork, we an rename this field to `timestamp`.
        uint64 proposedAt;
        // Before the fork, this field is the L1 block number where this block is proposed.
        // After the fork, this is the L1 block number input for the anchor transaction.
        // In a later fork, we an rename this field to `anchorBlockId`.
        uint64 proposedIn;
        uint24 nextTransitionId;
        bool livenessBondReturned;
        // The ID of the transaction that is used to verify this block. However, if
        // this block is not verified as the last block in a batch, verifiedTransitionId
        // will remain zero.
        uint24 verifiedTransitionId;
    }

    /// @dev Struct representing state transition data.
    /// 6 slots used.
    struct TransitionState {
        bytes32 key; // slot 1, only written/read for the 1st state transition.
        bytes32 blockHash; // slot 2
        bytes32 stateRoot; // slot 3
        address prover; // slot 4
        uint96 validityBond;
        address contester; // slot 5
        uint96 contestBond;
        uint64 timestamp; // slot 6 (90 bits)
        uint16 tier;
        uint8 __reserved1;
    }

    /// @dev Forge is only able to run coverage in case the contracts by default
    /// capable of compiling without any optimization (neither optimizer runs,
    /// no compiling --via-ir flag).
    /// In order to resolve stack too deep without optimizations, we needed to
    /// introduce outsourcing vars into structs below.
    struct SlotA {
        uint64 genesisHeight;
        uint64 genesisTimestamp;
        uint64 lastSyncedBlockId;
        uint64 lastSynecdAt; // typo!
    }

    struct SlotB {
        uint64 numBlocks;
        uint64 lastVerifiedBlockId;
        bool provingPaused;
        uint8 __reservedB1;
        uint16 __reservedB2;
        uint32 __reservedB3;
        uint64 lastUnpausedAt;
    }

    /// @dev Struct holding the state variables for the {TaikoL1} contract.
    struct State {
        // Ring buffer for proposed blocks and a some recent verified blocks.
        mapping(uint64 => BlockV2) blocks;
        // Indexing to transition ids (ring buffer not possible)
        mapping(uint64 => mapping(bytes32 => uint24)) transitionIds;
        // Ring buffer for transitions
        mapping(uint64 => mapping(uint32 => TransitionState)) transitions;
        bytes32 __reserve1; // Used as a ring buffer for Ether deposits
        SlotA slotA; // slot 5
        SlotB slotB; // slot 6
        mapping(address => uint256) bondBalance;
        uint256[43] __gap;
    }
}
