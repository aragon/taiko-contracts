// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IPluginSetup, PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../../src/Multisig.sol";
import {EmergencyMultisig} from "../../src/EmergencyMultisig.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {ERC20VotesMock} from "../mocks/ERC20VotesMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {createProxyAndCall} from "../helpers/proxy.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {TaikoL1Mock, TaikoL1PausedMock, TaikoL1WithOldLastBlock} from "../mocks/TaikoL1Mock.sol";
import {TaikoL1} from "../../src/adapted-dependencies/TaikoL1.sol";
import {ALICE_ADDRESS, BOB_ADDRESS, CAROL_ADDRESS, DAVID_ADDRESS, TAIKO_BRIDGE_ADDRESS} from "../constants.sol";
import {Test} from "forge-std/Test.sol";

contract AragonTest is Test {
    address immutable alice = ALICE_ADDRESS;
    address immutable bob = BOB_ADDRESS;
    address immutable carol = CAROL_ADDRESS;
    address immutable david = DAVID_ADDRESS;
    address immutable taikoBridge = TAIKO_BRIDGE_ADDRESS;
    address immutable randomWallet = vm.addr(1234567890);

    address immutable DAO_BASE = address(new DAO());
    address immutable MULTISIG_BASE = address(new Multisig());
    address immutable EMERGENCY_MULTISIG_BASE = address(new EmergencyMultisig());
    address immutable OPTIMISTIC_BASE = address(new OptimisticTokenVotingPlugin());
    address immutable VOTING_TOKEN_BASE = address(new ERC20VotesMock());

    bytes internal constant EMPTY_BYTES = "";

    constructor() {
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");
        vm.label(david, "David");
        vm.label(taikoBridge, "Bridge");
        vm.label(randomWallet, "Random wallet");
    }

    /// @notice Tells Foundry to continue executing from the given wallet.
    function switchTo(address target) internal {
        vm.startPrank(target);
    }

    /// @notice Tells Foundry to stop using the last labeled wallet.
    function undoSwitch() internal {
        vm.stopPrank();
    }

    /// @notice Returns the address and private key associated to the given label.
    /// @param label The label to get the address and private key for.
    /// @return addr The address associated with the label.
    /// @return pk The private key associated with the label.
    function getWallet(string memory label) internal returns (address addr, uint256 pk) {
        pk = uint256(keccak256(abi.encodePacked(label)));
        addr = vm.addr(pk);
        vm.label(addr, label);
    }

    /// @notice Moves the EVM time forward by a given amount.
    /// @param time The amount of seconds to advance.
    function timeForward(uint256 time) internal {
        vm.warp(block.timestamp + time);
    }

    /// @notice Moves the EVM time back by a given amount.
    /// @param time The amount of seconds to subtract.
    function timeBack(uint256 time) internal {
        vm.warp(block.timestamp - time);
    }

    /// @notice Sets the EVM timestamp.
    /// @param timestamp The timestamp in seconds.
    function setTime(uint256 timestamp) internal {
        vm.warp(timestamp);
    }

    /// @notice Moves the EVM block number forward by a given amount.
    /// @param blocks The number of blocks to advance.
    function blockForward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }

    /// @notice Moves the EVM block number back by a given amount.
    /// @param blocks The number of blocks to subtract.
    function blockBack(uint256 blocks) internal {
        vm.roll(block.number - blocks);
    }

    /// @notice Set the EVM block number to the given value.
    /// @param blockNumber The new block number
    function setBlock(uint256 blockNumber) internal {
        vm.roll(blockNumber);
    }
}
