// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20VotesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract ERC20VotesMock is ERC20Upgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("Mock Token", "MOCK");
        __ERC20Permit_init("Mock Token");
        __ERC20Votes_init();
    }

    function clock() public view override returns (uint48) {
        return SafeCastUpgradeable.toUint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        // See https://eips.ethereum.org/EIPS/eip-6372
        return "mode=timestamp";
    }

    // The functions below are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._mint(to, amount);
    }

    function _delegate(address delegator, address delegatee) internal override(ERC20VotesUpgradeable) {
        super._delegate(delegator, delegatee);
    }

    function _burn(address account, uint256 amount) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._burn(account, amount);
    }

    function mint() external {
        _mint(msg.sender, 10 ether);
    }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function mintAndDelegate(address receiver, uint256 amount) external {
        _mint(receiver, amount);
        _delegate(receiver, receiver);
    }
}
