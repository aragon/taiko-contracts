// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import "../src/training/TrainingDAO.sol";
import "../src/training/TrainingPingPong.sol";
import "../src/training/TrainingToken.sol";

contract DeployTrainingDAO is Script {
    // holesky
    address constant daoAddress = 0x05E0113B709e377a0882244B81a6B54f521c880f;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        DAO upgraded = new TrainingDAO();

        // Get creation code
        bytes memory creationCode = vm.getCode("TrainingDAO.sol:TrainingDAO");

        // Log the calldata (creation code + encoded constructor args)
        console.logBytes(creationCode);

        console.log("Deployed TrainingDAO at:", address(upgraded));

        // deploy the pin-pong contract
        TrainingPingPong pingPong = new TrainingPingPong(daoAddress);
        console.log("Deployed TrainingPingPong at:", address(pingPong));
        // deploy the token contract
        TrainingToken token = new TrainingToken(daoAddress);
        console.log("Deployed TrainingToken at:", address(token));
    }
}
