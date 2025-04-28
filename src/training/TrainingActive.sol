// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

// Contract to allow disabling the other Training contracts
contract TrainingActive is Ownable {
    bool public disabled;

    error AlreadyDisabled();

    modifier onlyWhenActive() {
        if (disabled) revert AlreadyDisabled();
        _;
    }

    constructor(address _dao) Ownable() {
        _transferOwnership(_dao);
    }

    event Disabled(address indexed sender);
    // allow to disable the contract irreversibly after training is over

    function disable() external virtual onlyOwner {
        disabled = true;
        emit Disabled(_msgSender());
    }
}
