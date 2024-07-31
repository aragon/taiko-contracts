// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Manual copy of lib/taiko-mono/packages/protocol/contracts/L1/TaikoL1.sol and its dependent structs
/// This is in order to overcome the conflicting compiler versions between 0.8.17 (OSx) and 0.8.24 (Taiko)
abstract contract TaikoL1 {
    TaikoData.State public state;

    /// @notice Returns true if the contract is paused, and false otherwise.
    /// @return true if paused, false otherwise.
    function paused() external view virtual returns (bool);

    /// @notice Gets SlotB
    /// @return  State variables stored at SlotB.
    function slotB() public view virtual returns (TaikoData.SlotB memory);

    function getBlock(uint64 _blockId) public view virtual returns (TaikoData.Block memory);
    function getLastVerifiedBlock()
        public
        view
        virtual
        returns (uint64 blockId_, bytes32 blockHash_, bytes32 stateRoot_);
}

library TaikoData {
    /// @dev Struct containing data required for verifying a block.
    /// 3 slots used.
    struct Block {
        bytes32 metaHash; // slot 1
        address assignedProver; // slot 2
        uint96 livenessBond;
        uint64 blockId; // slot 3
        uint64 proposedAt; // timestamp
        uint64 proposedIn; // L1 block number, required/used by node/client.
        uint32 nextTransitionId;
        uint32 verifiedTransitionId;
    }

    /// @dev Struct representing state transition data.
    /// 10 slots reserved for upgradability, 6 slots used.
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
        mapping(uint64 => Block) blocks;
        // Indexing to transition ids (ring buffer not possible)
        mapping(uint64 => mapping(bytes32 => uint32)) transitionIds;
        // Ring buffer for transitions
        mapping(uint64 => mapping(uint32 => TransitionState)) transitions;
        // Ring buffer for Ether deposits
        bytes32 __reserve1;
        SlotA slotA; // slot 5
        SlotB slotB; // slot 6
        uint256[44] __gap;
    }
}
