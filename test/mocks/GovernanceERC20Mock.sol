// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {ERC20VotesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

contract GovernanceERC20Mock is GovernanceERC20 {
    constructor(address _dao)
        GovernanceERC20(
            IDAO(_dao),
            "Mock Votes token",
            "MTK",
            MintSettings({amounts: new uint256[](0), receivers: new address[](0)})
        )
    {
        // MintSettings memory _mintSettings = MintSettings({amounts: new uint256[](0), receivers: new address[](0)});
    }

    function clock() public view override returns (uint48) {
        return SafeCastUpgradeable.toUint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        // See https://eips.ethereum.org/EIPS/eip-6372
        return "mode=timestamp";
    }

    function _mint(address to, uint256 amount) internal override {
        super._mint(to, amount);
    }

    function _delegate(address delegator, address delegatee) internal override(ERC20VotesUpgradeable) {
        super._delegate(delegator, delegatee);
    }

    function _burn(address account, uint256 amount) internal override {
        super._burn(account, amount);
    }

    function mint() external {
        _mint(msg.sender, 10 ether);
    }

    function mintTo(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function mintAndDelegate(address receiver, uint256 amount) external {
        _mint(receiver, amount);
        _delegate(receiver, receiver);
    }
}
