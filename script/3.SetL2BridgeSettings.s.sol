// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {L2VetoAggregation} from "../src/L2VetoAggregation.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract Deploy is Script {
    address l2VetoAggregation;
    address l2LzEndpoint;
    address l1Plugin;
    uint16 l1ChainId;

    function setUp() public {
        l2VetoAggregation = vm.envAddress("L2_VETO_AGGREGATION");
        l2LzEndpoint = vm.envAddress("LZ_L2_ENDPOINT");
        l1Plugin = vm.envAddress("L1_PLUGIN");
        l1ChainId = uint16(vm.envUint("L1_CHAIN_ID"));
    }

    function run() public {
        // 0. Setting up Foundry
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // 1. Create the seetings for the L2 Bridge
        L2VetoAggregation.BridgeSettings
            memory l2BridgeSettings = L2VetoAggregation.BridgeSettings(
                l1ChainId,
                l2LzEndpoint,
                l1Plugin
            );

        // 2. Initialize the L2 Veto Aggregation
        L2VetoAggregation(l2VetoAggregation).initialize(l2BridgeSettings);

        vm.stopBroadcast();
    }
}
