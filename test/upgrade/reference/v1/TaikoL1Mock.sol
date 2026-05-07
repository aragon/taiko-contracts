// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ITaikoL1} from "./adapted-dependencies/ITaikoL1.sol";

/// @dev Mock for V1 ITaikoL1 interface (getLastVerifiedBlock)
contract TaikoL1Mock is ITaikoL1 {
    function paused() public pure override returns (bool) {
        return false;
    }

    function getLastVerifiedBlock() external view override returns (uint64, bytes32, bytes32, uint64) {
        return (1, bytes32(0), bytes32(0), uint64(block.timestamp) - 1);
    }
}
