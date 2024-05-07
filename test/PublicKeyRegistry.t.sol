// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {PublicKeyRegistry} from "../src/PublicKeyRegistry.sol";
import {createProxyAndCall} from "./helpers.sol";

contract EmergencyMultisigTest is AragonTest {
    PublicKeyRegistry registry;

    // Events/errors to be tested here (duplicate)
    event PublicKeyRegistered(address wallet, bytes32 publicKey);

    error AlreadySet();

    function setUp() public {
        vm.startPrank(alice);
    }

    function test_Implement() public {
        vm.skip(true);
    }
}
