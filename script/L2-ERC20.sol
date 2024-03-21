// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Deploy is Script {
    function run() public {
        // 0. Setting up foundry
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the ERC-20 token
        ERC20 _token = new ERC20(
            "Tempan DAO Token",
            "TPT"
        );

        vm.stopBroadcast();
    }
}