// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {VetoToken} from "../src/VetoToken.sol";

contract Deploy is Script {
    function run() public {
        // 0. Setting up foundry
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploying the token
        new VetoToken();

        vm.stopBroadcast();
    }
}