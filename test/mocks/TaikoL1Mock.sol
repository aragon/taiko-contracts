// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import {TaikoL1, TaikoData} from "../../src/adapted-dependencies/TaikoL1.sol";

/// @dev Returns an unpaused TaikoL1 with any given block proposed 1 second ago
contract TaikoL1Mock is TaikoL1 {
    function paused() external pure override returns (bool) {
        return false;
    }

    function slotB() public pure override returns (TaikoData.SlotB memory result) {
        result.numBlocks = 90;
    }

    function getBlock(uint64 _blockId) public view override returns (TaikoData.Block memory result) {
        _blockId;
        result.proposedAt = uint64(block.timestamp) - 1;
    }
}

/// @dev Returns a paused TaikoL1
contract TaikoL1PausedMock is TaikoL1 {
    function paused() external pure override returns (bool) {
        return true;
    }

    function slotB() public view override returns (TaikoData.SlotB memory result) {}
    function getBlock(uint64 _blockId) public view override returns (TaikoData.Block memory) {}
}

contract TaikoL1WithOldLastBlock is TaikoL1 {
    function paused() external pure override returns (bool) {
        return false;
    }

    function slotB() public pure override returns (TaikoData.SlotB memory result) {
        result.numBlocks = 0;
    }

    function getBlock(uint64 _blockId) public pure override returns (TaikoData.Block memory result) {
        _blockId;
        result.proposedAt = 1;
    }
}
