// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {L2VetoReceiver} from "../../src/crosschain/L2VetoReceiver.sol";
import {IL2VetoReceiver} from "../../src/interfaces/IL2VetoReceiver.sol";
import {IBridge} from "../../src/interfaces/IBridge.sol";
import {TaikoBridgeMock} from "../mocks/TaikoBridgeMock.sol";

contract L2VetoReceiverTest is Test {
    L2VetoReceiver public receiver;
    TaikoBridgeMock public bridge;

    address public trustedAggregator = address(0xA66e6A702);
    uint64 public l2ChainId = 167000;

    event L2VetosReceived(bytes32 indexed proposalRef, uint256 vetoTally, uint256 dispatchedAt);

    function setUp() public {
        bridge = new TaikoBridgeMock();
        receiver = new L2VetoReceiver(address(bridge), trustedAggregator, l2ChainId);
    }

    // =========================================================================
    // CONSTRUCTOR TESTS
    // =========================================================================

    function test_constructor_setsImmutables() public view {
        assertEq(receiver.bridge(), address(bridge));
        assertEq(receiver.trustedL2Aggregator(), trustedAggregator);
        assertEq(receiver.l2ChainId(), l2ChainId);
    }

    function test_constructor_revert_zeroBridge() public {
        vm.expectRevert(IL2VetoReceiver.InvalidAddress.selector);
        new L2VetoReceiver(address(0), trustedAggregator, l2ChainId);
    }

    function test_constructor_revert_zeroAggregator() public {
        vm.expectRevert(IL2VetoReceiver.InvalidAddress.selector);
        new L2VetoReceiver(address(bridge), address(0), l2ChainId);
    }

    function test_constructor_revert_zeroChainId() public {
        vm.expectRevert(IL2VetoReceiver.InvalidAddress.selector);
        new L2VetoReceiver(address(bridge), trustedAggregator, 0);
    }

    // =========================================================================
    // RECEIVE VETOES TESTS
    // =========================================================================

    function test_onMessageInvocation_success() public {
        bytes32 proposalRef = keccak256("proposal1");
        uint256 vetoTally = 1000 ether;
        uint256 dispatchedAt = block.timestamp;

        // Prepare bridge context
        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        // Encode the data
        bytes memory data = abi.encode(proposalRef, vetoTally, dispatchedAt);

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit L2VetosReceived(proposalRef, vetoTally, dispatchedAt);

        // Call as bridge
        vm.prank(address(bridge));
        receiver.onMessageInvocation(data);

        // Verify storage
        assertEq(receiver.getL2VetoTally(proposalRef), vetoTally);
        assertEq(receiver.getL2DispatchTimestamp(proposalRef), dispatchedAt);
        assertTrue(receiver.hasReceivedL2Vetoes(proposalRef));
    }

    function test_onMessageInvocation_zeroVetoTally() public {
        bytes32 proposalRef = keccak256("proposal-with-zero-vetoes");
        uint256 vetoTally = 0;
        uint256 dispatchedAt = block.timestamp;

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        bytes memory data = abi.encode(proposalRef, vetoTally, dispatchedAt);

        vm.prank(address(bridge));
        receiver.onMessageInvocation(data);

        // Zero tally is valid and should be stored
        assertEq(receiver.getL2VetoTally(proposalRef), 0);
        assertEq(receiver.getL2DispatchTimestamp(proposalRef), dispatchedAt);
        assertTrue(receiver.hasReceivedL2Vetoes(proposalRef));
    }

    function test_onMessageInvocation_revert_callerNotBridge() public {
        bytes memory data = abi.encode(bytes32(0), uint256(0), uint256(1));

        vm.expectRevert(IL2VetoReceiver.CallerNotBridge.selector);
        receiver.onMessageInvocation(data);
    }

    function test_onMessageInvocation_revert_callerNotBridge_fromRandomAddress() public {
        address attacker = address(0xBAD);

        bytes memory data = abi.encode(bytes32(0), uint256(0), uint256(1));

        vm.prank(attacker);
        vm.expectRevert(IL2VetoReceiver.CallerNotBridge.selector);
        receiver.onMessageInvocation(data);
    }

    function test_onMessageInvocation_revert_untrustedSender() public {
        address attacker = address(0xA77AC3e2);

        // Set context with wrong sender
        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: attacker, srcChainId: l2ChainId}));

        bytes memory data = abi.encode(bytes32(0), uint256(0), uint256(1));

        vm.prank(address(bridge));
        vm.expectRevert(IL2VetoReceiver.UntrustedL2Sender.selector);
        receiver.onMessageInvocation(data);
    }

    function test_onMessageInvocation_revert_invalidSourceChain() public {
        uint64 wrongChainId = 999;

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: wrongChainId}));

        bytes memory data = abi.encode(bytes32(0), uint256(0), uint256(1));

        vm.prank(address(bridge));
        vm.expectRevert(IL2VetoReceiver.InvalidSourceChain.selector);
        receiver.onMessageInvocation(data);
    }

    function test_onMessageInvocation_replacesWithNewerTimestamp() public {
        bytes32 proposalRef = keccak256("proposal1");

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        // First call with 1000 vetoes at timestamp 100
        bytes memory data1 = abi.encode(proposalRef, uint256(1000 ether), uint256(100));
        vm.prank(address(bridge));
        receiver.onMessageInvocation(data1);

        assertEq(receiver.getL2VetoTally(proposalRef), 1000 ether);
        assertEq(receiver.getL2DispatchTimestamp(proposalRef), 100);

        // Second call with 2000 vetoes at newer timestamp 200 - should replace
        bytes memory data2 = abi.encode(proposalRef, uint256(2000 ether), uint256(200));
        vm.prank(address(bridge));
        receiver.onMessageInvocation(data2);

        assertEq(receiver.getL2VetoTally(proposalRef), 2000 ether);
        assertEq(receiver.getL2DispatchTimestamp(proposalRef), 200);
    }

    function test_onMessageInvocation_revert_staleMessage_sameTimestamp() public {
        bytes32 proposalRef = keccak256("proposal1");

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        // First call
        bytes memory data1 = abi.encode(proposalRef, uint256(1000), uint256(100));
        vm.prank(address(bridge));
        receiver.onMessageInvocation(data1);

        // Second call with same timestamp reverts
        bytes memory data2 = abi.encode(proposalRef, uint256(2000), uint256(100));
        vm.prank(address(bridge));
        vm.expectRevert(IL2VetoReceiver.StaleVetoMessage.selector);
        receiver.onMessageInvocation(data2);
    }

    function test_onMessageInvocation_revert_staleMessage_olderTimestamp() public {
        bytes32 proposalRef = keccak256("proposal1");

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        // First call at timestamp 200
        bytes memory data1 = abi.encode(proposalRef, uint256(1000), uint256(200));
        vm.prank(address(bridge));
        receiver.onMessageInvocation(data1);

        // Second call with older timestamp 100 reverts
        bytes memory data2 = abi.encode(proposalRef, uint256(2000), uint256(100));
        vm.prank(address(bridge));
        vm.expectRevert(IL2VetoReceiver.StaleVetoMessage.selector);
        receiver.onMessageInvocation(data2);
    }

    function test_onMessageInvocation_multipleProposals() public {
        bytes32 proposalRef1 = keccak256("proposal1");
        bytes32 proposalRef2 = keccak256("proposal2");

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        // First proposal
        vm.prank(address(bridge));
        receiver.onMessageInvocation(abi.encode(proposalRef1, uint256(1000), block.timestamp));

        // Second proposal
        vm.prank(address(bridge));
        receiver.onMessageInvocation(abi.encode(proposalRef2, uint256(2000), block.timestamp + 1));

        // Both stored correctly
        assertEq(receiver.getL2VetoTally(proposalRef1), 1000);
        assertEq(receiver.getL2VetoTally(proposalRef2), 2000);
    }

    // =========================================================================
    // VIEW FUNCTION TESTS
    // =========================================================================

    function test_getL2VetoTally_returnsZeroForUnknown() public view {
        assertEq(receiver.getL2VetoTally(bytes32("unknown")), 0);
    }

    function test_getL2DispatchTimestamp_returnsZeroForUnknown() public view {
        assertEq(receiver.getL2DispatchTimestamp(bytes32("unknown")), 0);
    }

    function test_hasReceivedL2Vetoes_returnsFalseForUnknown() public view {
        assertFalse(receiver.hasReceivedL2Vetoes(bytes32("unknown")));
    }

    // =========================================================================
    // FUZZ TESTS
    // =========================================================================

    function testFuzz_onMessageInvocation(bytes32 proposalRef, uint256 vetoTally, uint256 dispatchedAt) public {
        // Assume non-zero dispatchedAt to avoid collision with "not received" state
        vm.assume(dispatchedAt > 0);

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        bytes memory data = abi.encode(proposalRef, vetoTally, dispatchedAt);

        vm.prank(address(bridge));
        receiver.onMessageInvocation(data);

        assertEq(receiver.getL2VetoTally(proposalRef), vetoTally);
        assertEq(receiver.getL2DispatchTimestamp(proposalRef), dispatchedAt);
        assertTrue(receiver.hasReceivedL2Vetoes(proposalRef));
    }

    function testFuzz_constructor_validParams(address _bridge, address _aggregator, uint64 _chainId) public {
        vm.assume(_bridge != address(0));
        vm.assume(_aggregator != address(0));
        vm.assume(_chainId > 0);

        L2VetoReceiver newReceiver = new L2VetoReceiver(_bridge, _aggregator, _chainId);

        assertEq(newReceiver.bridge(), _bridge);
        assertEq(newReceiver.trustedL2Aggregator(), _aggregator);
        assertEq(newReceiver.l2ChainId(), _chainId);
    }

    // =========================================================================
    // INTEGRATION WITH TAIKO BRIDGE MOCK
    // =========================================================================

    function test_integration_processMessage_fromMockBridge() public {
        bytes32 proposalRef = keccak256("integration-test-proposal");
        uint256 vetoTally = 5000 ether;
        uint256 dispatchedAt = block.timestamp;

        // Create a mock L2 aggregator message
        bytes memory vetoData = abi.encode(proposalRef, vetoTally, dispatchedAt);

        // Create bridge message
        IBridge.Message memory message = IBridge.Message({
            id: 0,
            fee: 0,
            gasLimit: 100000,
            from: trustedAggregator,
            srcChainId: l2ChainId,
            srcOwner: trustedAggregator,
            destChainId: uint64(block.chainid),
            destOwner: address(receiver),
            to: address(receiver),
            value: 0,
            data: abi.encodeCall(receiver.onMessageInvocation, (vetoData))
        });

        // Process message through mock bridge (simulates what happens on L1)
        (IBridge.Status status,) = bridge.processMessage(message, "");

        assertEq(uint256(status), uint256(IBridge.Status.DONE));
        assertEq(receiver.getL2VetoTally(proposalRef), vetoTally);
        assertTrue(receiver.hasReceivedL2Vetoes(proposalRef));
    }
}
