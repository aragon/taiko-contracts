// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import {TaikoL1, TaikoData} from "../../src/adapted-dependencies/TaikoL1.sol";

/// @dev Returns an unpaused TaikoL1 with any given block proposed 1 second ago
contract TaikoL1Mock is TaikoL1 {
    function paused() public pure override returns (bool) {
        return false;
    }

    function getStateVariables()
        public
        pure
        override
        returns (TaikoData.SlotA memory slotA, TaikoData.SlotB memory slotB)
    {
        slotA;
        slotB.numBlocks = 90;
    }

    function getBlockV2(uint64) public view override returns (TaikoData.BlockV2 memory blk) {
        blk.proposedAt = uint64(block.timestamp) - 1;
    }
}

/// @dev Returns a paused TaikoL1
contract TaikoL1PausedMock is TaikoL1 {
    function paused() public pure override returns (bool) {
        return true;
    }

    function getStateVariables()
        public
        pure
        override
        returns (TaikoData.SlotA memory slotA, TaikoData.SlotB memory slotB)
    {
        slotA;
        slotB.numBlocks = 1;
    }

    function getBlockV2(uint64) public view override returns (TaikoData.BlockV2 memory) {}
}

contract TaikoL1WithOldLastBlock is TaikoL1 {
    function paused() public pure override returns (bool) {
        return false;
    }

    function getStateVariables()
        public
        pure
        override
        returns (TaikoData.SlotA memory slotA, TaikoData.SlotB memory slotB)
    {
        slotA;
        slotB.numBlocks = 1;
    }

    function getBlockV2(uint64) public pure override returns (TaikoData.BlockV2 memory blk) {
        blk.proposedAt = 1;
    }
}

contract TaikoL1Incompatible {}
