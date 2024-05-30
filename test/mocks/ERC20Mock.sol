// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("Mock token", "MOCK") {}

    function mint() external {
        _mint(msg.sender, 10 ether);
    }

    function mintTo(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}
