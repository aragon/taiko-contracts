// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./TrainingActive.sol";

// Trivial contract to exercise during the SC training program
contract TrainingToken is ERC20, TrainingActive {
    // Event to log token burns
    event TokensBurned(address indexed sender, uint256 amount);

    error ReceiverNotAllowed();
    // The constructor mints 1 million tokens to the deployer

    constructor(address _owner) TrainingActive(_owner) ERC20("TrainingToken", "TT") {
        _mint(_owner, 1000000 * 10 ** decimals());
    }

    // Override the transfer function to burn tokens when they're sent to this contract
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        super._afterTokenTransfer(from, to, amount);

        // If tokens are transferred to this contract, burn them
        if (to == address(this)) {
            _burn(address(this), amount);
            emit TokensBurned(from, amount);
        }
    }

    // Override _beforeTokenTransfer to prevent transfers when disabled
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);

        if (disabled && totalSupply() > 0) {
            revert AlreadyDisabled();
        }
        // allow recipients to be self, the dao, or 0x0 for burning
        if (to != address(0x0) && to != address(this) && to != address(owner())) {
            revert ReceiverNotAllowed();
        }
    }
    // Override disable method to burn all tokens

    function disable() external override onlyOwner {
        // Burn all tokens from the contract itself
        if (balanceOf(address(this)) > 0) {
            _burn(address(this), balanceOf(address(this)));
        }

        // Burn all remaining tokens from the owner
        if (balanceOf(owner()) > 0) {
            _burn(owner(), balanceOf(owner()));
        }
        // Default behavior
        disabled = true;
        emit Disabled(_msgSender());
    }
}
