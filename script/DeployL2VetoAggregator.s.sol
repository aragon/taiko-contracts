// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {L2VetoAggregator} from "../src/crosschain/L2VetoAggregator.sol";

contract DeployL2VetoAggregator is Script {
    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));
        _;
        vm.stopBroadcast();
    }

    function run() external broadcast {
        address bridge = vm.envAddress("L2_TAIKO_BRIDGE");
        uint64 l1ChainId = uint64(vm.envUint("L1_CHAIN_ID"));
        address votingToken = vm.envAddress("L2_VOTING_TOKEN");
        address l1Receiver = vm.envAddress("VETO_RECEIVER_ADDRESS");

        L2VetoAggregator aggregator = new L2VetoAggregator(bridge, l1ChainId, votingToken, l1Receiver);

        console.log("L2VetoAggregator deployed:", address(aggregator));
        console.log("  bridge:", bridge);
        console.log("  l1ChainId:", l1ChainId);
        console.log("  votingToken:", votingToken);
        console.log("  l1Receiver (immutable):", l1Receiver);

        string memory key = "l2-deployments";
        string memory json = vm.serializeAddress(key, "l2VetoAggregator", address(aggregator));

        string memory dir = string.concat(vm.projectRoot(), "/proposals");
        vm.createDir(dir, true);
        vm.writeFile(string.concat(dir, "/l2-deployments.json"), json);
        console.log("Wrote proposals/l2-deployments.json");
    }
}
