// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {EncryptionRegistry} from "../src/EncryptionRegistry.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../src/Multisig.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract EncryptionRegistryTest is AragonTest {
    EncryptionRegistry registry;
    DaoBuilder builder;
    DAO dao;
    Multisig multisig;

    // Events/errors to be tested here (duplicate)

    function setUp() public {
        // builder = new DaoBuilder();
        // (dao,, multisig,,,) = builder.withMultisigMember(alice).withMultisigMember(bob).withMultisigMember(carol)
        //     .withMultisigMember(david).build();

        // registry = new EncryptionRegistry(multisig);
    }

    function test_AAA() public {}
}
