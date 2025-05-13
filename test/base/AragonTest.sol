// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IPluginSetup, PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../../src/Multisig.sol";
import {EmergencyMultisig} from "../../src/EmergencyMultisig.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {createProxyAndCall} from "../../src/helpers/proxy.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {TaikoL1Mock, TaikoL1PausedMock, TaikoL1WithOldLastBlock} from "../mocks/TaikoL1Mock.sol";
import {ITaikoL1} from "../../src/adapted-dependencies/ITaikoL1.sol";
import {
    ALICE_ADDRESS,
    BOB_ADDRESS,
    CAROL_ADDRESS,
    DAVID_ADDRESS,
    TAIKO_BRIDGE_ADDRESS,
    EXCLUDED_VOTING_POWER_HOLDER_1,
    EXCLUDED_VOTING_POWER_HOLDER_2
} from "../constants.sol";
import {Test} from "forge-std/Test.sol";

contract AragonTest is Test {
    address immutable alice = ALICE_ADDRESS;
    address immutable bob = BOB_ADDRESS;
    address immutable carol = CAROL_ADDRESS;
    address immutable david = DAVID_ADDRESS;
    address immutable taikoBridge = TAIKO_BRIDGE_ADDRESS;
    address immutable excludedVotingPowerHolder1 = EXCLUDED_VOTING_POWER_HOLDER_1;
    address immutable excludedVotingPowerHolder2 = EXCLUDED_VOTING_POWER_HOLDER_2;
    address immutable randomWallet = vm.addr(1234567890);

    address immutable DAO_BASE = address(new DAO());
    address immutable MULTISIG_BASE = address(new Multisig());
    address immutable EMERGENCY_MULTISIG_BASE = address(new EmergencyMultisig());
    address immutable OPTIMISTIC_BASE = address(new OptimisticTokenVotingPlugin());

    bytes internal constant EMPTY_BYTES = "";

    constructor() {
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");
        vm.label(david, "David");
        vm.label(taikoBridge, "Bridge");
        vm.label(excludedVotingPowerHolder1, "Excluded voting power holder 1");
        vm.label(excludedVotingPowerHolder2, "Excluded voting power holder 2");
        vm.label(randomWallet, "Random wallet");
    }

    /// @notice Returns the address and private key associated to the given name.
    /// @param name The name to get the address and private key for.
    /// @return addr The address associated with the name.
    /// @return pk The private key associated with the name.
    function getWallet(string memory name) internal returns (address addr, uint256 pk) {
        pk = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(pk);
        vm.label(addr, name);
    }

    /// @notice Returns a predefined list of excluded voting power holders.
    function getExcludedVotingPowerHolders() internal view returns (address[] memory excluded) {
        excluded = new address[](2);
        excluded[0] = excludedVotingPowerHolder1;
        excluded[1] = excludedVotingPowerHolder2;
        return excluded;
    }
}
