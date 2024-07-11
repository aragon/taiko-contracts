// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {DelegationWall} from "../src/DelegationWall.sol";
import {createProxyAndCall} from "../src/helpers/proxy.sol";

contract EmergencyMultisigTest is AragonTest {
    DelegationWall wall;

    /// @notice Emitted when a wallet registers as a candidate
    event CandidateRegistered(address indexed candidate, bytes contentUrl);

    /// @notice Raised when a delegate registers with an empty contentUrl
    error EmptyContent();

    function setUp() public {
        wall = new DelegationWall();
    }

    function test_ShouldRegisterACandidate() public {
        wall.register("ipfs://1234");

        vm.startPrank(alice);
        wall.register("ipfs://abcdef");

        vm.startPrank(bob);
        wall.register("ipfs://xyz");

        vm.startPrank(carol);
        wall.register("ipfs://____");

        vm.startPrank(david);
        wall.register("ipfs://1234000");
    }

    function test_ShouldRevertIfEmptyContent() public {
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(EmptyContent.selector));
        wall.register("");

        // Not revert
        wall.register(" ");

        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(EmptyContent.selector));
        wall.register("");

        // Not revert
        wall.register(" ");
    }

    function test_ShouldStoreCandidateDetails() public {
        // Alice
        vm.startPrank(alice);
        wall.register("ipfs://alice");

        bytes memory contentUrl = wall.candidates(alice);
        assertEq(contentUrl, "ipfs://alice", "Incorrect delegate contentUrl");

        // Bob
        vm.startPrank(bob);

        wall.register("ipfs://bob");
        (contentUrl) = wall.candidates(bob);
        assertEq(contentUrl, "ipfs://bob", "Incorrect delegate contentUrl");

        // Carol
        vm.startPrank(carol);

        wall.register("ipfs://carol");
        (contentUrl) = wall.candidates(carol);
        assertEq(contentUrl, "ipfs://carol", "Incorrect delegate contentUrl");

        // David
        vm.startPrank(david);

        wall.register("ipfs://david");
        (contentUrl) = wall.candidates(david);
        assertEq(contentUrl, "ipfs://david", "Incorrect delegate contentUrl");
    }

    function test_ShouldUpdateCandidateDetails() public {
        // Alice
        vm.startPrank(alice);
        wall.register("ipfs://alice");

        bytes memory contentUrl = wall.candidates(alice);
        assertEq(contentUrl, "ipfs://alice", "Incorrect delegate contentUrl");

        // update
        wall.register("ipfs://alice-2");
        (contentUrl) = wall.candidates(alice);
        assertEq(contentUrl, "ipfs://alice-2", "Incorrect delegate contentUrl");

        // Bob
        vm.startPrank(bob);

        wall.register("ipfs://bob");
        (contentUrl) = wall.candidates(bob);
        assertEq(contentUrl, "ipfs://bob", "Incorrect delegate contentUrl");

        // update
        wall.register("ipfs://bob-2");
        (contentUrl) = wall.candidates(bob);
        assertEq(contentUrl, "ipfs://bob-2", "Incorrect delegate contentUrl");
    }

    function test_ShouldCountRegisteredCandidates() public {
        assertEq(wall.candidateCount(), 0, "Incorrect candidate count");

        // Alice
        vm.startPrank(alice);
        wall.register("ipfs://alice");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");

        // Bob
        vm.startPrank(bob);
        wall.register("ipfs://bob");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");

        // Carol
        vm.startPrank(carol);
        wall.register("ipfs://carol");
        assertEq(wall.candidateCount(), 3, "Incorrect candidate count");

        // David
        vm.startPrank(david);
        wall.register("ipfs://david");
        assertEq(wall.candidateCount(), 4, "Incorrect candidate count");
    }

    function test_ShouldKeepTheCountWhenRegisteringAnExistingCandidate() public {
        assertEq(wall.candidateCount(), 0, "Incorrect candidate count");

        // Alice
        vm.startPrank(alice);
        wall.register("ipfs://alice");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("ipfs://alice");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("ipfs://alice");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("Alice");
        assertEq(wall.candidateCount(), 1, "Incorrect candidate count");
        wall.register("Vote Alice");

        // Bob
        vm.startPrank(bob);
        wall.register("ipfs://bob");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-1");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-2");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-3");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-4");
        assertEq(wall.candidateCount(), 2, "Incorrect candidate count");
        wall.register("ipfs://bob-5");
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
        wall.register("ipfs://alice");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(1), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(2), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // Bob
        vm.startPrank(bob);
        wall.register("ipfs://bob");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(1), bob, "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(2), address(0), "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // Carol
        vm.startPrank(carol);
        wall.register("ipfs://carol");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(1), bob, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(2), carol, "Incorrect candidate address");
        vm.expectRevert();
        assertEq(wall.candidateAddresses(3), address(0), "Incorrect candidate address");

        // David
        vm.startPrank(david);
        wall.register("ipfs://david");

        assertEq(wall.candidateAddresses(0), alice, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(1), bob, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(2), carol, "Incorrect candidate address");
        assertEq(wall.candidateAddresses(3), david, "Incorrect candidate address");
    }

    function test_ShouldEmitAnEventWhenRegistering() public {
        // Alice
        vm.startPrank(alice);
        vm.expectEmit();
        emit CandidateRegistered(alice, "ipfs://alice");
        wall.register("ipfs://alice");

        // Bob
        vm.startPrank(bob);
        vm.expectEmit();
        emit CandidateRegistered(bob, "ipfs://bob");
        wall.register("ipfs://bob");

        // Carol
        vm.startPrank(carol);
        vm.expectEmit();
        emit CandidateRegistered(carol, "ipfs://carol");
        wall.register("ipfs://carol");

        // David
        vm.startPrank(david);
        vm.expectEmit();
        emit CandidateRegistered(david, "ipfs://david");
        wall.register("ipfs://david");
    }
}
