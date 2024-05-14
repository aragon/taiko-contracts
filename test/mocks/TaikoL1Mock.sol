// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ITaikoEssentialContract} from "../../src/interfaces/ITaikoEssentialContract.sol";

contract TaikoL1UnpausedMock is ITaikoEssentialContract {
    function pause() external {}
    function unpause() external {}

    function impl() external view returns (address) {
        return address(this);
    }

    function paused() external pure returns (bool) {
        return false;
    }

    function inNonReentrant() external view returns (bool) {}
}

contract TaikoL1PausedMock is ITaikoEssentialContract {
    function pause() external {}
    function unpause() external {}

    function impl() external view returns (address) {
        return address(this);
    }

    function paused() external pure returns (bool) {
        return true;
    }

    function inNonReentrant() external view returns (bool) {}
}
