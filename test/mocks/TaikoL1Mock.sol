// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import {ITaikoL1} from "../../src/adapted-dependencies/ITaikoL1.sol";

/// @dev Returns an unpaused TaikoL1 with the last finalized timestamp 1 second ago
contract TaikoL1Mock is ITaikoL1 {
    function paused() public pure override returns (bool) {
        return false;
    }

    function getCoreState() external view override returns (CoreState memory coreState) {
        coreState.lastFinalizedTimestamp = uint48(block.timestamp) - 1;
    }
}

/// @dev Returns a paused TaikoL1
contract TaikoL1PausedMock is ITaikoL1 {
    function paused() public pure override returns (bool) {
        return true;
    }

    function getCoreState() external pure override returns (CoreState memory coreState) {
        coreState.lastFinalizedTimestamp = 0;
    }
}

contract TaikoL1WithOldLastBlock is ITaikoL1 {
    function paused() public pure override returns (bool) {
        return false;
    }

    function getCoreState() external pure override returns (CoreState memory coreState) {
        coreState.lastFinalizedTimestamp = 1;
    }
}

contract TaikoL1Incompatible {}
