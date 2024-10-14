// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {EncryptionRegistry} from "../src/EncryptionRegistry.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../src/Multisig.sol";

contract EncryptionRegistryTest is AragonTest {
    EncryptionRegistry registry;
    DaoBuilder builder;
    Multisig multisig;

    // Events/errors to be tested here (duplicate)
    event PublicKeyRegistered(address wallet, bytes32 publicKey);

    function setUp() public {
        builder = new DaoBuilder();
        (,, multisig,,,) = builder.withMultisigMember(alice).withMultisigMember(bob).withMultisigMember(carol)
            .withMultisigMember(david).build();

        registry = new EncryptionRegistry(multisig);
    }

    function test_ShouldAppointWallets() public {
        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.appointWallet(address(0x1234000000000000000000000000000000000000));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));

        // Bob
        vm.startPrank(bob);
        registry.appointWallet(address(0x0000567800000000000000000000000000000000));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(0x0000000090aB0000000000000000000000000000));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000000090aB0000000000000000000000000000));

        // David
        vm.startPrank(david);
        registry.appointWallet(address(0x000000000000cdEf000000000000000000000000));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x1234000000000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000567800000000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x0000000090aB0000000000000000000000000000));
        (addrValue, bytesValue) = registry.members(david);
        assertEq(bytesValue, 0);
        assertEq(addrValue, address(0x000000000000cdEf000000000000000000000000));
    }

    function test_ShouldRegisterOwnPublicKeys() public {
        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(david);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function testFuzz_ShouldRegisterMemberPublicKeys(address appointedWallet) public {
        if (appointedWallet == address(0)) return;

        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.appointWallet(address(appointedWallet));
        vm.startPrank(appointedWallet);
        registry.setPublicKey(alice, 0x1234000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.appointWallet(address(appointedWallet));
        vm.startPrank(appointedWallet);
        registry.setPublicKey(bob, 0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.appointWallet(address(appointedWallet));
        vm.startPrank(appointedWallet);
        registry.setPublicKey(carol, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.appointWallet(address(appointedWallet));
        vm.startPrank(appointedWallet);
        registry.setPublicKey(david, 0x000000000000cdef000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(david);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function test_ShouldWipePublicKeyAfterAppointing(address appointedWallet) public {
        if (appointedWallet == address(0)) return;

        address addrValue;
        bytes32 bytesValue;

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, address(0));
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);
        registry.appointWallet(address(appointedWallet));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);
        registry.appointWallet(address(appointedWallet));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);
        registry.appointWallet(address(appointedWallet));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);
        registry.appointWallet(address(appointedWallet));

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x1234000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000567800000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(david);
        assertEq(addrValue, appointedWallet);
        assertEq(bytesValue, 0x000000000000cdef000000000000000000000000000000000000000000000000);
    }

    function test_ShouldRevertWhenAppointingContracts() public {
        revert("");
    }

    function test_ShouldRevertIfNotAppointed() public {
        revert("");
    }

    function test_ShouldRevertIfNotListed_PublicKeySelf() public {
        address addrValue;
        bytes32 bytesValue;

        (,, multisig,,,) = new DaoBuilder().withMultisigMember(alice).build();

        registry = new EncryptionRegistry(multisig);

        // OK
        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Alice
        vm.startPrank(alice);
        assertEq(multisig.isMember(alice), true);
        registry.setOwnPublicKey(0x5678000000000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x5678000000000000000000000000000000000000000000000000000000000000);

        // NOT OK

        // Bob
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x5678000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, bob);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // Carol
        vm.startPrank(carol);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x5678000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, bob);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, carol);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);

        // David
        vm.startPrank(david);
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.RegistrationForbidden.selector));
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        (addrValue, bytesValue) = registry.members(alice);
        assertEq(addrValue, alice);
        assertEq(bytesValue, 0x5678000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(bob);
        assertEq(addrValue, bob);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(carol);
        assertEq(addrValue, carol);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
        (addrValue, bytesValue) = registry.members(david);
        assertEq(addrValue, david);
        assertEq(bytesValue, 0x0000000000000000000000000000000000000000000000000000000000000000);
    }

    function test_ShouldRevertIfNotListed_PublicKeyAppointee() public {
        revert("");
    }

    function test_ShouldRevertIfNotListed_AppointWallet() public {
        revert("");
    }

    function test_PublicKeyShouldBeEmptyAfterAppointing() public {
        revert("");
    }

    function test_ShouldEmitPublicKeyDefinedEvents() public {
        // For itself
        vm.startPrank(alice);
        vm.expectEmit();
        emit PublicKeyRegistered(alice, 0x000000000000cdef000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x000000000000cdef000000000000000000000000000000000000000000000000);

        vm.startPrank(bob);
        vm.expectEmit();
        emit PublicKeyRegistered(bob, 0x0000000090ab0000000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x0000000090ab0000000000000000000000000000000000000000000000000000);

        vm.startPrank(carol);
        vm.expectEmit();
        emit PublicKeyRegistered(carol, 0x0000567800000000000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x0000567800000000000000000000000000000000000000000000000000000000);

        vm.startPrank(david);
        vm.expectEmit();
        emit PublicKeyRegistered(david, 0x1234000000000000000000000000000000000000000000000000000000000000);
        registry.setOwnPublicKey(0x1234000000000000000000000000000000000000000000000000000000000000);

        // As the appointee
        revert("to do");
    }

    function test_ShouldCountRegisteredCandidates() public {
        assertEq(registry.getRegisteredAddressesLength(), 0, "Incorrect count");

        // Alice
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        assertEq(registry.getRegisteredAddressesLength(), 1, "Incorrect count");

        // Bob
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        assertEq(registry.getRegisteredAddressesLength(), 2, "Incorrect count");

        // Carol
        vm.startPrank(carol);
        registry.setOwnPublicKey(bytes32(uint256(3456)));
        assertEq(registry.getRegisteredAddressesLength(), 3, "Incorrect count");

        // David
        vm.startPrank(david);
        registry.setOwnPublicKey(bytes32(uint256(4567)));
        assertEq(registry.getRegisteredAddressesLength(), 4, "Incorrect count");
    }

    function test_ShouldEnumerateRegisteredCandidates() public {
        // Register
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        vm.startPrank(carol);
        registry.setOwnPublicKey(bytes32(uint256(3456)));
        vm.startPrank(david);
        registry.setOwnPublicKey(bytes32(uint256(4567)));

        assertEq(registry.getRegisteredAddressesLength(), 4, "Incorrect count");

        assertEq(registry.registeredAddresses(0), alice);
        assertEq(registry.registeredAddresses(1), bob);
        assertEq(registry.registeredAddresses(2), carol);
        assertEq(registry.registeredAddresses(3), david);
    }

    function test_ShouldLoadTheRegisteredAddresses() public {
        vm.startPrank(alice);
        registry.setOwnPublicKey(bytes32(uint256(1234)));
        vm.startPrank(bob);
        registry.setOwnPublicKey(bytes32(uint256(2345)));
        vm.startPrank(carol);
        registry.setOwnPublicKey(bytes32(uint256(3456)));
        vm.startPrank(david);
        registry.setOwnPublicKey(bytes32(uint256(4567)));

        address[] memory candidates = registry.getRegisteredAddresses();
        assertEq(candidates.length, 4);
        assertEq(candidates[0], alice);
        assertEq(candidates[1], bob);
        assertEq(candidates[2], carol);
        assertEq(candidates[3], david);
    }

    function test_TheConstructorShouldRevertIfInvalidAddressList() public {
        // Fail
        vm.expectRevert(abi.encodeWithSelector(EncryptionRegistry.InvalidAddressList.selector));
        new EncryptionRegistry(Addresslist(address(this)));

        // OK
        (,, multisig,,,) = new DaoBuilder().withMultisigMember(alice).build();
        new EncryptionRegistry(multisig);
    }

    /// @dev mock function for test_TheConstructorShouldRevertIfInvalidAddressList()
    function supportsInterface(bytes4) public pure returns (bool) {
        return false;
    }
}
