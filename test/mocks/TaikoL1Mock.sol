// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import {TaikoL1, TaikoData} from "../../src/adapted-dependencies/TaikoL1.sol";

contract TaikoL1UnpausedMock is TaikoL1 {
    function paused() external pure override returns (bool) {
        return false;
    }

    function slotB() public view override returns (TaikoData.SlotB memory) {}

    function getBlock(uint64 _blockId) public view override returns (TaikoData.Block memory) {}
}

contract TaikoL1PausedMock is TaikoL1 {
    function paused() external pure override returns (bool) {
        return true;
    }

    function slotB() public view override returns (TaikoData.SlotB memory) {}

    function getBlock(uint64 _blockId) public view override returns (TaikoData.Block memory) {}
}
