// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
// Trivial upgrade to exercise during the SC training program

contract TrainingDAO is DAO {
    function isTrainingExecuted() external pure returns (bool) {
        return true;
    }
}
