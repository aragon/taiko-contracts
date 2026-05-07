// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {L2VetoReceiver} from "../../src/crosschain/L2VetoReceiver.sol";
import {IL2VetoReceiver} from "../../src/interfaces/IL2VetoReceiver.sol";
import {IBridge} from "../../src/interfaces/IBridge.sol";
import {TaikoBridgeMock} from "../mocks/TaikoBridgeMock.sol";
import {OptimisticTokenVotingPluginMock} from "../mocks/OptimisticTokenVotingPluginMock.sol";
import {createProxyAndCall} from "../../src/helpers/proxy.sol";
import {ProposalIdCodec} from "../../src/libs/ProposalIdCodec.sol";

contract L2VetoReceiverTest is Test {
    L2VetoReceiver public receiver;
    TaikoBridgeMock public bridge;
    OptimisticTokenVotingPluginMock public plugin;
    DAO public dao;

    address public trustedAggregator = address(0xA66e6A702);
    uint64 public l2ChainId = 167000;

    // Test proposal values
    uint64 public constant PROPOSAL_COUNTER = 1;
    uint64 public constant PROPOSAL_START = 1000;
    uint64 public constant PROPOSAL_END = 2000;
    uint64 public constant PROPOSAL_SNAPSHOT = 999;

    event L2VetoTallyBridged(uint256 indexed proposalId, uint256 vetoTally, uint256 dispatchedAt);
    event SubmitVetoSuccess(uint256 indexed proposalId, uint256 vetoTally);
    event SubmitVetoFailed(uint256 indexed proposalId, uint256 vetoTally, bytes revertData);
    event TrustedL2AggregatorUpdated(address oldAggregator, address newAggregator);

    function setUp() public {
        dao = DAO(
            payable(
                createProxyAndCall(address(new DAO()), abi.encodeCall(DAO.initialize, ("", address(this), address(0), "")))
            )
        );

        bridge = new TaikoBridgeMock();
        plugin = new OptimisticTokenVotingPluginMock();
        receiver = new L2VetoReceiver(IDAO(address(dao)), address(bridge), l2ChainId, address(plugin));

        // Grant SET_TRUSTED_L2_AGGREGATOR_PERMISSION to this test contract
        dao.grant(
            address(receiver),
            address(this),
            receiver.SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID()
        );

        receiver.setTrustedL2Aggregator(trustedAggregator);
    }

    /// @notice Helper to create a valid proposalId with encoded timestamps
    function _makeProposalId() internal pure returns (uint256) {
        return ProposalIdCodec.encode(PROPOSAL_SNAPSHOT, PROPOSAL_START, PROPOSAL_END, PROPOSAL_COUNTER);
    }

    /// @notice Helper to set up a valid proposal in the mock plugin
    function _setupValidProposal() internal returns (uint256 proposalId) {
        proposalId = _makeProposalId();
        plugin.setProposal(proposalId, PROPOSAL_START, PROPOSAL_END, PROPOSAL_SNAPSHOT);
    }

    // =========================================================================
    // CONSTRUCTOR TESTS
    // =========================================================================

    function test_constructor_setsImmutables() public view {
        assertEq(receiver.bridge(), address(bridge));
        assertEq(receiver.l2ChainId(), l2ChainId);
        assertEq(receiver.votingPlugin(), address(plugin));
        assertEq(address(receiver.dao()), address(dao));
    }

    function test_constructor_revert_zeroBridge() public {
        vm.expectRevert(IL2VetoReceiver.InvalidAddress.selector);
        new L2VetoReceiver(IDAO(address(dao)), address(0), l2ChainId, address(plugin));
    }

    function test_constructor_revert_zeroChainId() public {
        vm.expectRevert(IL2VetoReceiver.InvalidAddress.selector);
        new L2VetoReceiver(IDAO(address(dao)), address(bridge), 0, address(plugin));
    }

    function test_constructor_revert_zeroPlugin() public {
        vm.expectRevert(IL2VetoReceiver.InvalidAddress.selector);
        new L2VetoReceiver(IDAO(address(dao)), address(bridge), l2ChainId, address(0));
    }

    // =========================================================================
    // SET TRUSTED L2 AGGREGATOR TESTS
    // =========================================================================

    function test_setTrustedL2Aggregator_success() public {
        L2VetoReceiver newReceiver =
            new L2VetoReceiver(IDAO(address(dao)), address(bridge), l2ChainId, address(plugin));

        dao.grant(
            address(newReceiver),
            address(this),
            newReceiver.SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID()
        );

        address newAggregator = address(0x1234567890);

        vm.expectEmit(true, true, false, false);
        emit TrustedL2AggregatorUpdated(address(0), newAggregator);

        newReceiver.setTrustedL2Aggregator(newAggregator);

        assertEq(newReceiver.trustedL2Aggregator(), newAggregator);
    }

    function test_setTrustedL2Aggregator_revert_zeroAddress() public {
        vm.expectRevert(IL2VetoReceiver.InvalidAddress.selector);
        receiver.setTrustedL2Aggregator(address(0));
    }

    function test_setTrustedL2Aggregator_revert_unauthorized() public {
        address notAuthorized = address(0xBAD);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(receiver),
                notAuthorized,
                receiver.SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID()
            )
        );
        vm.prank(notAuthorized);
        receiver.setTrustedL2Aggregator(address(0x123));
    }

    function test_setTrustedL2Aggregator_canUpdate() public {
        address newAggregator = address(0x999);

        vm.expectEmit(true, true, false, false);
        emit TrustedL2AggregatorUpdated(trustedAggregator, newAggregator);

        receiver.setTrustedL2Aggregator(newAggregator);

        assertEq(receiver.trustedL2Aggregator(), newAggregator);
    }

    // =========================================================================
    // RECEIVE VETOES TESTS
    // =========================================================================

    function test_onMessageInvocation_success() public {
        uint256 proposalId = _setupValidProposal();
        uint256 vetoTally = 1000 ether;
        uint256 dispatchedAt = block.timestamp;

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        bytes memory data = abi.encode(proposalId, vetoTally, dispatchedAt);

        vm.expectEmit(true, false, false, true);
        emit L2VetoTallyBridged(proposalId, vetoTally, dispatchedAt);

        vm.expectEmit(true, false, false, true);
        emit SubmitVetoSuccess(proposalId, vetoTally);

        vm.prank(address(bridge));
        receiver.onMessageInvocation(data);

        // Verify receiver storage
        assertEq(receiver.getL2VetoTally(proposalId), vetoTally);
        assertEq(receiver.getL2DispatchTimestamp(proposalId), dispatchedAt);
        assertTrue(receiver.hasReceivedL2Vetoes(proposalId));

        // Verify plugin received the vetoes
        assertEq(plugin.lastReceivedProposalId(), proposalId);
        assertEq(plugin.lastReceivedVetoTally(), vetoTally);
    }

    function test_onMessageInvocation_zeroVetoTally() public {
        uint256 proposalId = _setupValidProposal();
        uint256 vetoTally = 0;
        uint256 dispatchedAt = block.timestamp;

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        bytes memory data = abi.encode(proposalId, vetoTally, dispatchedAt);

        vm.prank(address(bridge));
        receiver.onMessageInvocation(data);

        assertEq(receiver.getL2VetoTally(proposalId), 0);
        assertEq(receiver.getL2DispatchTimestamp(proposalId), dispatchedAt);
        assertTrue(receiver.hasReceivedL2Vetoes(proposalId));
    }

    function test_onMessageInvocation_revert_callerNotBridge() public {
        uint256 proposalId = _setupValidProposal();
        bytes memory data = abi.encode(proposalId, uint256(0), uint256(1));

        vm.expectRevert(IL2VetoReceiver.CallerNotBridge.selector);
        receiver.onMessageInvocation(data);
    }

    function test_onMessageInvocation_revert_untrustedSender() public {
        uint256 proposalId = _setupValidProposal();
        address attacker = address(0xA77AC3e2);

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: attacker, srcChainId: l2ChainId}));

        bytes memory data = abi.encode(proposalId, uint256(0), uint256(1));

        vm.prank(address(bridge));
        vm.expectRevert(IL2VetoReceiver.UntrustedL2Sender.selector);
        receiver.onMessageInvocation(data);
    }

    function test_onMessageInvocation_revert_invalidSourceChain() public {
        uint256 proposalId = _setupValidProposal();
        uint64 wrongChainId = 999;

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: wrongChainId}));

        bytes memory data = abi.encode(proposalId, uint256(0), uint256(1));

        vm.prank(address(bridge));
        vm.expectRevert(IL2VetoReceiver.InvalidSourceChain.selector);
        receiver.onMessageInvocation(data);
    }

    function test_onMessageInvocation_revert_invalidProposalId() public {
        // Create a proposalId that doesn't match any proposal in the plugin
        uint256 invalidProposalId = 999;

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        bytes memory data = abi.encode(invalidProposalId, uint256(1000), uint256(1));

        vm.prank(address(bridge));
        vm.expectRevert(L2VetoReceiver.InvalidProposalId.selector);
        receiver.onMessageInvocation(data);
    }

    function test_onMessageInvocation_replacesWithNewerTimestamp() public {
        uint256 proposalId = _setupValidProposal();

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        // First call with 1000 vetoes at timestamp 100
        bytes memory data1 = abi.encode(proposalId, uint256(1000 ether), uint256(100));
        vm.prank(address(bridge));
        receiver.onMessageInvocation(data1);

        assertEq(receiver.getL2VetoTally(proposalId), 1000 ether);
        assertEq(receiver.getL2DispatchTimestamp(proposalId), 100);

        // Second call with 2000 vetoes at newer timestamp 200 - should replace
        bytes memory data2 = abi.encode(proposalId, uint256(2000 ether), uint256(200));
        vm.prank(address(bridge));
        receiver.onMessageInvocation(data2);

        assertEq(receiver.getL2VetoTally(proposalId), 2000 ether);
        assertEq(receiver.getL2DispatchTimestamp(proposalId), 200);
    }

    function test_onMessageInvocation_revert_staleMessage_sameTimestamp() public {
        uint256 proposalId = _setupValidProposal();

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        bytes memory data1 = abi.encode(proposalId, uint256(1000), uint256(100));
        vm.prank(address(bridge));
        receiver.onMessageInvocation(data1);

        bytes memory data2 = abi.encode(proposalId, uint256(2000), uint256(100));
        vm.prank(address(bridge));
        vm.expectRevert(IL2VetoReceiver.StaleVetoMessage.selector);
        receiver.onMessageInvocation(data2);
    }

    function test_onMessageInvocation_revert_staleMessage_olderTimestamp() public {
        uint256 proposalId = _setupValidProposal();

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        bytes memory data1 = abi.encode(proposalId, uint256(1000), uint256(200));
        vm.prank(address(bridge));
        receiver.onMessageInvocation(data1);

        bytes memory data2 = abi.encode(proposalId, uint256(2000), uint256(100));
        vm.prank(address(bridge));
        vm.expectRevert(IL2VetoReceiver.StaleVetoMessage.selector);
        receiver.onMessageInvocation(data2);
    }

    // =========================================================================
    // SUBMIT L2 VETOES TESTS
    // =========================================================================

    function test_submitL2Vetoes_revert_noVotes() public {
        uint256 proposalId = _setupValidProposal();

        vm.expectRevert(L2VetoReceiver.NoVotesToSubmit.selector);
        receiver.submitL2Vetoes(proposalId);
    }

    function test_submitL2Vetoes_canResubmit() public {
        uint256 proposalId = _setupValidProposal();
        uint256 vetoTally = 1000 ether;
        uint256 dispatchedAt = block.timestamp;

        bridge.setContext(IBridge.Context({msgHash: bytes32(0), from: trustedAggregator, srcChainId: l2ChainId}));

        bytes memory data = abi.encode(proposalId, vetoTally, dispatchedAt);

        vm.prank(address(bridge));
        receiver.onMessageInvocation(data);

        // Can call submitL2Vetoes again
        vm.expectEmit(true, false, false, true);
        emit SubmitVetoSuccess(proposalId, vetoTally);

        receiver.submitL2Vetoes(proposalId);
    }

    // =========================================================================
    // VIEW FUNCTION TESTS
    // =========================================================================

    function test_getL2VetoTally_returnsZeroForUnknown() public view {
        assertEq(receiver.getL2VetoTally(999), 0);
    }

    function test_getL2DispatchTimestamp_returnsZeroForUnknown() public view {
        assertEq(receiver.getL2DispatchTimestamp(999), 0);
    }

    function test_hasReceivedL2Vetoes_returnsFalseForUnknown() public view {
        assertFalse(receiver.hasReceivedL2Vetoes(999));
    }

    function test_isProposalIdValid_returnsTrueForValidProposal() public {
        uint256 proposalId = _setupValidProposal();
        assertTrue(receiver.isProposalIdValid(proposalId));
    }

    function test_isProposalIdValid_returnsFalseForInvalidProposal() public view {
        assertFalse(receiver.isProposalIdValid(999));
    }

    // =========================================================================
    // FUZZ TESTS
    // =========================================================================

    function testFuzz_constructor_validParams(address _bridge, uint64 _chainId, address _plugin) public {
        vm.assume(_bridge != address(0));
        vm.assume(_chainId > 0);
        vm.assume(_plugin != address(0));

        L2VetoReceiver newReceiver = new L2VetoReceiver(IDAO(address(dao)), _bridge, _chainId, _plugin);

        assertEq(newReceiver.bridge(), _bridge);
        assertEq(newReceiver.l2ChainId(), _chainId);
        assertEq(newReceiver.votingPlugin(), _plugin);
        assertEq(address(newReceiver.dao()), address(dao));
    }

    // =========================================================================
    // INTEGRATION WITH TAIKO BRIDGE MOCK
    // =========================================================================

    function test_integration_processMessage_fromMockBridge() public {
        uint256 proposalId = _setupValidProposal();
        uint256 vetoTally = 5000 ether;
        uint256 dispatchedAt = block.timestamp;

        bytes memory vetoData = abi.encode(proposalId, vetoTally, dispatchedAt);

        IBridge.Message memory message = IBridge.Message({
            id: 0,
            fee: 0,
            gasLimit: 200000,
            from: trustedAggregator,
            srcChainId: l2ChainId,
            srcOwner: trustedAggregator,
            destChainId: uint64(block.chainid),
            destOwner: address(receiver),
            to: address(receiver),
            value: 0,
            data: abi.encodeCall(receiver.onMessageInvocation, (vetoData))
        });

        (IBridge.Status status,) = bridge.processMessage(message, "");

        assertEq(uint256(status), uint256(IBridge.Status.DONE));
        assertEq(receiver.getL2VetoTally(proposalId), vetoTally);
        assertTrue(receiver.hasReceivedL2Vetoes(proposalId));
        assertEq(plugin.l2VetoTallies(proposalId), vetoTally);
    }
}
