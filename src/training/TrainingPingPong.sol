// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./TrainingActive.sol";

// Trivial contract to exercise during the SC training program
contract TrainingPingPong is TrainingActive {
    uint256 public pingCount;

    event Pong();

    constructor(address _dao) TrainingActive(_dao) {}

    function ping() external onlyWhenActive onlyOwner {
        pingCount++;
        emit Pong();
    }
}
