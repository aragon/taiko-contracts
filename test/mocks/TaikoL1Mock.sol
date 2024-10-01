// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import {TaikoL1} from "../../src/adapted-dependencies/TaikoL1.sol";

/// @dev Returns an unpaused TaikoL1 with any given block proposed 1 second ago
contract TaikoL1Mock is TaikoL1 {
    function paused() public pure override returns (bool) {
        return false;
    }

    function getLastVerifiedBlock()
        external
        view
        override
        returns (uint64 blockId, bytes32 blockHash, bytes32 stateRoot, uint64 verifiedAt)
    {
        blockId = 0; // irrelevant
        blockHash = bytes32(0); // irrelevant
        stateRoot = bytes32(0); // irrelevant
        verifiedAt = uint64(block.timestamp) - 1;
    }
}

/// @dev Returns a paused TaikoL1
contract TaikoL1PausedMock is TaikoL1 {
    function paused() public pure override returns (bool) {
        return true;
    }

    function getLastVerifiedBlock()
        external
        pure
        override
        returns (uint64 blockId, bytes32 blockHash, bytes32 stateRoot, uint64 verifiedAt)
    {
        blockId = 0; // irrelevant
        blockHash = bytes32(0); // irrelevant
        stateRoot = bytes32(0); // irrelevant
        verifiedAt = 0;
    }
}

contract TaikoL1WithOldLastBlock is TaikoL1 {
    function paused() public pure override returns (bool) {
        return false;
    }

    function getLastVerifiedBlock()
        external
        pure
        override
        returns (uint64 blockId, bytes32 blockHash, bytes32 stateRoot, uint64 verifiedAt)
    {
        blockId = 0; // irrelevant
        blockHash = bytes32(0); // irrelevant
        stateRoot = bytes32(0); // irrelevant
        verifiedAt = 1;
    }
}

contract TaikoL1Incompatible {}
