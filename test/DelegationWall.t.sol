// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {DelegationWall} from "../src/DelegationWall.sol";
import {createProxyAndCall} from "../src/helpers/proxy.sol";

contract EmergencyMultisigTest is AragonTest {
    DelegationWall wall;

    /// @notice Emitted when a wallet registers as a candidate
    event CandidateRegistered(address indexed candidate, bytes contentUrl, bytes socialUrl);

    /// @notice Raised when a delegate registers with an empty contentUrl
    error EmptyContent();

    function setUp() public {
        wall = new DelegationWall();
    }

    function test_ShouldRegisterACandidate() public {
        wall.register("ipfs://1234", "");

        vm.startPrank(alice);
        wall.register("ipfs://abcdef", "");

        vm.startPrank(bob);
        wall.register("ipfs://xyz", " ");

        vm.startPrank(carol);
        wall.register("ipfs://____", "https://taiko.xyz/");

        vm.startPrank(david);
        wall.register("ipfs://1234000", "https://aragon.org/");
    }

    function test_ShouldRevertIfEmptyContent() public {
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(EmptyContent.selector));
        wall.register("", "");
        vm.expectRevert(abi.encodeWithSelector(EmptyContent.selector));
        wall.register("", "https://taiko.xyz/");

        // Not revert
        wall.register(" ", "https://taiko.xyz/");

        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(EmptyContent.selector));
        wall.register("", "");
        vm.expectRevert(abi.encodeWithSelector(EmptyContent.selector));
        wall.register("", "https://taiko.xyz/");

        // Not revert
        wall.register(" ", "https://taiko.xyz/");
    }

    function test_ShouldStoreCandidateDetails() public {
        // Alice
        vm.startPrank(alice);
        wall.register("ipfs://alice", "https://");

        (bytes memory contentUrl, bytes memory url) = wall.candidates(alice);
        assertEq(contentUrl, "ipfs://alice", "Incorrect delegate contentUrl");
        assertEq(url, "https://", "Incorrect social URL");

        // Bob
        vm.startPrank(bob);

        wall.register("ipfs://bob", "https://taiko.xyz");
        (contentUrl, url) = wall.candidates(bob);
        assertEq(contentUrl, "ipfs://bob", "Incorrect delegate contentUrl");
        assertEq(url, "https://taiko.xyz", "Incorrect social URL");

        // Carol
        vm.startPrank(carol);

        wall.register("ipfs://carol", "https://x.com/carol");
        (contentUrl, url) = wall.candidates(carol);
        assertEq(contentUrl, "ipfs://carol", "Incorrect delegate contentUrl");
        assertEq(url, "https://x.com/carol", "Incorrect social URL");

        // David
        vm.startPrank(david);

        wall.register("ipfs://david", "https://defeat-goliath.org");
        (contentUrl, url) = wall.candidates(david);
        assertEq(contentUrl, "ipfs://david", "Incorrect delegate contentUrl");
        assertEq(url, "https://defeat-goliath.org", "Incorrect social URL");
    }

    function test_ShouldUpdateCandidateDetails() public {
        // Alice
        vm.startPrank(alice);
        wall.register("ipfs://alice", "https://");

        (bytes memory contentUrl, bytes memory url) = wall.candidates(alice);
        assertEq(contentUrl, "ipfs://alice", "Incorrect delegate contentUrl");
        assertEq(url, "https://", "Incorrect social URL");

        // update
        wall.register("ipfs://alice-2", "https://alice-for-president.org");
        (contentUrl, url) = wall.candidates(alice);
        assertEq(contentUrl, "ipfs://alice-2", "Incorrect delegate contentUrl");
        assertEq(url, "https://alice-for-president.org", "Incorrect social URL");

        // Bob
        vm.startPrank(bob);

        wall.register("ipfs://bob", "https://taiko.xyz");
        (contentUrl, url) = wall.candidates(bob);
        assertEq(contentUrl, "ipfs://bob", "Incorrect delegate contentUrl");
        assertEq(url, "https://taiko.xyz", "Incorrect social URL");

        // update
        wall.register("ipfs://bob-2", "https://bob-president.org");
        (contentUrl, url) = wall.candidates(bob);
        assertEq(contentUrl, "ipfs://bob-2", "Incorrect delegate contentUrl");
        assertEq(url, "https://bob-president.org", "Incorrect social URL");
    }

    function test_ShouldCountRegisteredCandidates() public {
        assertEq(wall.candidateCount(), 0, "Incorrect candidate count");

        // Alice
        vm.startPrank(alice);
        wall.register("ipfs://alice", "https://");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");

        // Bob
        vm.startPrank(bob);
        wall.register("ipfs://bob", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");

        // Carol
        vm.startPrank(carol);
        wall.register("ipfs://carol", "https://x.com/carol");
        assertEq(wall.candidateCount(), 3, "Incorrect candidate count");

        // David
        vm.startPrank(david);
        wall.register("ipfs://david", "https://defeat-goliath.org");
        assertEq(wall.candidateCount(), 4, "Incorrect candidate count");
    }

    function test_ShouldKeepTheCountWhenRegisteringAnExistingCandidate() public {
        assertEq(wall.candidateCount(), 0, "Incorrect candidate count");

        // Alice
        vm.startPrank(alice);
        wall.register("ipfs://alice", "https://");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("ipfs://alice", "https://");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("ipfs://alice", "https://");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("Alice", "https://alice-for-president.org");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("Vote Alice", "https://alice.land");

        // Bob
        vm.startPrank(bob);
        wall.register("ipfs://bob", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-1", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-2", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-3", "https://taiko.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-4", "https://bob.xyz");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-5", "https://bob.robot");
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
        wall.register("ipfs://alice", "https://");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(1), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(2), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // Bob
        vm.startPrank(bob);
        wall.register("ipfs://bob", "https://taiko.xyz");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(1), bob, "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(2), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // Carol
        vm.startPrank(carol);
        wall.register("ipfs://carol", "https://x.com/carol");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(1), bob, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(2), carol, "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // David
        vm.startPrank(david);
        wall.register("ipfs://david", "https://defeat-goliath.org");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(1), bob, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(2), carol, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(3), david, "Incorrect candidate address");
    }

    function test_ShouldEmitAnEventWhenRegistering() public {
        // Alice
        vm.startPrank(alice);
        vm.expectEmit();
        emit CandidateRegistered(alice, "ipfs://alice", "https://");
        wall.register("ipfs://alice", "https://");

        // Bob
        vm.startPrank(bob);
        vm.expectEmit();
        emit CandidateRegistered(bob, "ipfs://bob", "https://taiko.xyz");
        wall.register("ipfs://bob", "https://taiko.xyz");

        // Carol
        vm.startPrank(carol);
        vm.expectEmit();
        emit CandidateRegistered(carol, "ipfs://carol", "https://x.com/carol");
        wall.register("ipfs://carol", "https://x.com/carol");

        // David
        vm.startPrank(david);
        vm.expectEmit();
        emit CandidateRegistered(david, "ipfs://david", "https://defeat-goliath.org");
        wall.register("ipfs://david", "https://defeat-goliath.org");
    }
}
