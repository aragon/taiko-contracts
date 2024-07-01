// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {DelegationWall} from "../src/DelegationWall.sol";
import {createProxyAndCall} from "../src/helpers/proxy.sol";

contract EmergencyMultisigTest is AragonTest {
    DelegationWall wall;

    /// @notice Emitted when a wallet registers as a candidate
    event CandidateRegistered(address indexed candidate, bytes message, bytes socialUrl);

    /// @notice Raised when a delegate registers with an empty message
    error EmptyMessage();

    function setUp() public {
        wall = new DelegationWall();
    }

    function test_ShouldRegisterACandidate() public {
        wall.register("Hello world", "");

        vm.startPrank(alice);
        wall.register("Hi there", "");

        vm.startPrank(bob);
        wall.register("Hej there", " ");

        vm.startPrank(carol);
        wall.register("Good morning", "https://taiko.xyz/");

        vm.startPrank(david);
        wall.register("Bonjour", "https://aragon.org/");
    }

    function test_ShouldRevertIfEmptyMessage() public {
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(EmptyMessage.selector));
        wall.register("", "");
        vm.expectRevert(abi.encodeWithSelector(EmptyMessage.selector));
        wall.register("", "https://taiko.xyz/");

        // Not revert
        wall.register(" ", "https://taiko.xyz/");

        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(EmptyMessage.selector));
        wall.register("", "");
        vm.expectRevert(abi.encodeWithSelector(EmptyMessage.selector));
        wall.register("", "https://taiko.xyz/");

        // Not revert
        wall.register(" ", "https://taiko.xyz/");
    }

    function test_ShouldStoreCandidateDetails() public {
        // Alice
        vm.startPrank(alice);
        wall.register("I am Alice", "https://");

        (bytes memory message, bytes memory url) = wall.candidates(alice);
        assertEq(message, "I am Alice", "Incorrect delegate message");
        assertEq(url, "https://", "Incorrect social URL");

        // Bob
        vm.startPrank(bob);

        wall.register("Je suis Bob", "https://taiko.xyz");
        (message, url) = wall.candidates(bob);
        assertEq(message, "Je suis Bob", "Incorrect delegate message");
        assertEq(url, "https://taiko.xyz", "Incorrect social URL");

        // Carol
        vm.startPrank(carol);

        wall.register("I am Carol", "https://x.com/carol");
        (message, url) = wall.candidates(carol);
        assertEq(message, "I am Carol", "Incorrect delegate message");
        assertEq(url, "https://x.com/carol", "Incorrect social URL");

        // David
        vm.startPrank(david);

        wall.register("I am David", "https://defeat-goliath.org");
        (message, url) = wall.candidates(david);
        assertEq(message, "I am David", "Incorrect delegate message");
        assertEq(url, "https://defeat-goliath.org", "Incorrect social URL");
    }

    function test_ShouldUpdateCandidateDetails() public {
        // Alice
        vm.startPrank(alice);
        wall.register("I am Alice", "https://");

        (bytes memory message, bytes memory url) = wall.candidates(alice);
        assertEq(message, "I am Alice", "Incorrect delegate message");
        assertEq(url, "https://", "Incorrect social URL");

        // update
        wall.register("I am Alice 2.0", "https://alice-for-president.org");
        (message, url) = wall.candidates(alice);
        assertEq(message, "I am Alice 2.0", "Incorrect delegate message");
        assertEq(url, "https://alice-for-president.org", "Incorrect social URL");

        // Bob
        vm.startPrank(bob);

        wall.register("Je suis Bob", "https://taiko.xyz");
        (message, url) = wall.candidates(bob);
        assertEq(message, "Je suis Bob", "Incorrect delegate message");
        assertEq(url, "https://taiko.xyz", "Incorrect social URL");

        // update
        wall.register("Je suis Bob 2.0", "https://bob-president.org");
        (message, url) = wall.candidates(bob);
        assertEq(message, "Je suis Bob 2.0", "Incorrect delegate message");
        assertEq(url, "https://bob-president.org", "Incorrect social URL");
    }

    function test_ShouldCountRegisteredCandidates() public {
        assertEq(wall.candidateCount(), 0, "Incorrect candidate count");

        // Alice
        vm.startPrank(alice);
        wall.register("I am Alice", "https://");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");

        // Bob
        vm.startPrank(bob);
        wall.register("Je suis Bob", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");

        // Carol
        vm.startPrank(carol);
        wall.register("I am Carol", "https://x.com/carol");
        assertEq(wall.candidateCount(), 3, "Incorrect candidate count");

        // David
        vm.startPrank(david);
        wall.register("I am David", "https://defeat-goliath.org");
        assertEq(wall.candidateCount(), 4, "Incorrect candidate count");
    }

    function test_ShouldKeepTheCountWhenRegisteringAnExistingCandidate() public {
        assertEq(wall.candidateCount(), 0, "Incorrect candidate count");

        // Alice
        vm.startPrank(alice);
        wall.register("I am Alice", "https://");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("I am Alice", "https://");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("I am Alice", "https://");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("Alice", "https://alice-for-president.org");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("Vote Alice", "https://alice.land");

        // Bob
        vm.startPrank(bob);
        wall.register("Je suis Bob", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("Je suis Bob", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("Je suis Bob", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("Je suis Bob", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("Moi, je suis Bob", "https://bob.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("Bob the bot", "https://bob.robot");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
    }

    function test_ShouldRetrieveRegisteredCandidateAddresses() public {
        vm.expectRevert();
        assertEq(wall.candidateAddresses(0), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(1), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(2), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // Alice
        vm.startPrank(alice);
        wall.register("I am Alice", "https://");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(1), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(2), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // Bob
        vm.startPrank(bob);
        wall.register("Je suis Bob", "https://taiko.xyz");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(1), bob, "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(2), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // Carol
        vm.startPrank(carol);
        wall.register("I am Carol", "https://x.com/carol");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(1), bob, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(2), carol, "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // David
        vm.startPrank(david);
        wall.register("I am David", "https://defeat-goliath.org");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(1), bob, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(2), carol, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(3), david, "Incorrect candidate address");
    }

    function test_ShouldEmitAnEventWhenRegistering() public {
        // Alice
        vm.startPrank(alice);
        vm.expectEmit();
        emit CandidateRegistered(alice, "I am Alice", "https://");
        wall.register("I am Alice", "https://");

        // Bob
        vm.startPrank(bob);
        vm.expectEmit();
        emit CandidateRegistered(bob, "Je suis Bob", "https://taiko.xyz");
        wall.register("Je suis Bob", "https://taiko.xyz");

        // Carol
        vm.startPrank(carol);
        vm.expectEmit();
        emit CandidateRegistered(carol, "I am Carol", "https://x.com/carol");
        wall.register("I am Carol", "https://x.com/carol");

        // David
        vm.startPrank(david);
        vm.expectEmit();
        emit CandidateRegistered(david, "I am David", "https://defeat-goliath.org");
        wall.register("I am David", "https://defeat-goliath.org");
    }
}
