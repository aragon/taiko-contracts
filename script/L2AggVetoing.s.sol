// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {L2VetoAggregation} from "../src/L2VetoAggregation.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract L2VetoAggregationDeployment is Script {
    address votingToken;

    function setUp() public {
        votingToken = vm.envAddress("L2_TOKEN_ADDRESS");
    }

    function run() public {
        // 0. Setting up Foundry
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // 1. Deploy the voting agg
        L2VetoAggregation l2VetoAggregation = new L2VetoAggregation(
            IVotesUpgradeable(votingToken)
        );

        vm.stopBroadcast();
    }
}