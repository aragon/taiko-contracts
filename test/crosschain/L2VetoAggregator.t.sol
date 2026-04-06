// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {L2VetoAggregator} from "../../src/crosschain/L2VetoAggregator.sol";
import {IL2VetoAggregator} from "../../src/interfaces/IL2VetoAggregator.sol";
import {IBridge} from "../../src/interfaces/IBridge.sol";
import {IMessageInvocable} from "../../src/interfaces/IMessageInvocable.sol";
import {TaikoBridgeMock} from "../mocks/TaikoBridgeMock.sol";
import {GovernanceERC20Mock} from "../mocks/GovernanceERC20Mock.sol";
import {ProposalIdCodec} from "../../src/libs/ProposalIdCodec.sol";

contract L2VetoAggregatorTest is Test {
    L2VetoAggregator public aggregator;
    TaikoBridgeMock public bridge;
    GovernanceERC20Mock public token;

    address public l1Receiver = address(0x11C0DE);
    uint64 public l1ChainId = 1;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA201);

    // Proposal timing
    uint64 public constant SNAPSHOT = 999;
    uint64 public constant START = 1000;
    uint64 public constant END = 2000;
    uint64 public constant COUNTER = 1;

    event VetoCast(uint256 indexed proposalId, address indexed voter, uint256 votingPower);
    event VetoDispatched(uint256 indexed proposalId, uint256 vetoTally, bytes32 msgHash);

    function setUp() public {
        bridge = new TaikoBridgeMock();
        // GovernanceERC20Mock needs a DAO address, use a dummy
        token = new GovernanceERC20Mock(address(0xDA0));

        aggregator = new L2VetoAggregator(address(bridge), l1ChainId, address(token), l1Receiver);

        // Mint and delegate tokens to test voters
        // Warp to before SNAPSHOT so checkpoints are recorded before snapshot
        vm.warp(SNAPSHOT - 10);
        token.mintAndDelegate(alice, 100 ether);
        token.mintAndDelegate(bob, 50 ether);
        // Carol gets no tokens (zero voting power)

        // Advance past snapshot so getPastVotes works
        vm.warp(SNAPSHOT + 1);
    }

    // =========================================================================
    // HELPERS
    // =========================================================================

    function _makeProposalId() internal pure returns (uint256) {
        return ProposalIdCodec.encode(SNAPSHOT, START, END, COUNTER);
    }

    function _makeProposalId(
        uint64 snapshot,
        uint64 startDate,
        uint64 endDate,
        uint64 counter
    ) internal pure returns (uint256) {
        return ProposalIdCodec.encode(snapshot, startDate, endDate, counter);
    }

    // =========================================================================
    // CONSTRUCTOR TESTS
    // =========================================================================

    function test_constructor_setsImmutables() public view {
        assertEq(aggregator.bridge(), address(bridge));
        assertEq(aggregator.l1ChainId(), l1ChainId);
        assertEq(address(aggregator.votingToken()), address(token));
        assertEq(aggregator.l1Receiver(), l1Receiver);
    }

    function test_constructor_revert_zeroBridge() public {
        vm.expectRevert(IL2VetoAggregator.InvalidAddress.selector);
        new L2VetoAggregator(address(0), l1ChainId, address(token), l1Receiver);
    }

    function test_constructor_revert_zeroChainId() public {
        vm.expectRevert(IL2VetoAggregator.InvalidAddress.selector);
        new L2VetoAggregator(address(bridge), 0, address(token), l1Receiver);
    }

    function test_constructor_revert_zeroToken() public {
        vm.expectRevert(IL2VetoAggregator.InvalidAddress.selector);
        new L2VetoAggregator(address(bridge), l1ChainId, address(0), l1Receiver);
    }

    function test_constructor_revert_zeroL1Receiver() public {
        vm.expectRevert(IL2VetoAggregator.InvalidAddress.selector);
        new L2VetoAggregator(address(bridge), l1ChainId, address(token), address(0));
    }

    // =========================================================================
    // VETO TESTS
    // =========================================================================

    function test_veto_success() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START); // Within veto period

        vm.expectEmit(true, true, false, true);
        emit VetoCast(proposalId, alice, 100 ether);

        vm.prank(alice);
        aggregator.veto(proposalId);

        assertEq(aggregator.getVetoTally(proposalId), 100 ether);
        assertTrue(aggregator.hasVetoed(proposalId, alice));
    }

    function test_veto_multipleVoters() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(alice);
        aggregator.veto(proposalId);

        vm.prank(bob);
        aggregator.veto(proposalId);

        assertEq(aggregator.getVetoTally(proposalId), 150 ether);
        assertTrue(aggregator.hasVetoed(proposalId, alice));
        assertTrue(aggregator.hasVetoed(proposalId, bob));
    }

    function test_veto_revert_beforeStartDate() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START - 1); // Before start

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IL2VetoAggregator.ProposalVetoingForbidden.selector, proposalId, alice));
        aggregator.veto(proposalId);
    }

    function test_veto_revert_afterEndDate() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(END); // At endDate (not open, uses strict <)

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IL2VetoAggregator.ProposalVetoingForbidden.selector, proposalId, alice));
        aggregator.veto(proposalId);
    }

    function test_veto_revert_afterEndDate_wellPast() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(END + 1000);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IL2VetoAggregator.ProposalVetoingForbidden.selector, proposalId, alice));
        aggregator.veto(proposalId);
    }

    function test_veto_revert_alreadyVetoed() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(alice);
        aggregator.veto(proposalId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IL2VetoAggregator.ProposalVetoingForbidden.selector, proposalId, alice));
        aggregator.veto(proposalId);
    }

    function test_veto_revert_noVotingPower() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(carol); // Carol has no tokens
        vm.expectRevert(abi.encodeWithSelector(IL2VetoAggregator.ProposalVetoingForbidden.selector, proposalId, carol));
        aggregator.veto(proposalId);
    }

    function test_veto_atExactStartDate() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START); // Exactly at startDate

        vm.prank(alice);
        aggregator.veto(proposalId);

        assertEq(aggregator.getVetoTally(proposalId), 100 ether);
    }

    function test_veto_justBeforeEndDate() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(END - 1); // One second before endDate

        vm.prank(alice);
        aggregator.veto(proposalId);

        assertEq(aggregator.getVetoTally(proposalId), 100 ether);
    }

    // =========================================================================
    // DISPATCH TESTS
    // =========================================================================

    function test_dispatch_success() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(alice);
        aggregator.veto(proposalId);

        aggregator.dispatch(proposalId);

        // Verify bridge received the message
        IBridge.Message[] memory messages = bridge.getSentMessages();
        assertEq(messages.length, 1);
        assertEq(messages[0].to, l1Receiver);
        assertEq(messages[0].destChainId, l1ChainId);
        assertEq(messages[0].srcOwner, address(this));
        assertEq(messages[0].destOwner, address(this));
    }

    function test_dispatch_emitsEvent() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(alice);
        aggregator.veto(proposalId);

        // Just check that VetoDispatched is emitted (msgHash is dynamic)
        vm.expectEmit(true, false, false, false);
        emit VetoDispatched(proposalId, 100 ether, bytes32(0));

        aggregator.dispatch(proposalId);
    }

    function test_dispatch_revertsWithZeroTally() public {
        uint256 proposalId = _makeProposalId();

        // Dispatch with no votes — reverts
        vm.expectRevert(IL2VetoAggregator.NothingToDispatch.selector);
        aggregator.dispatch(proposalId);
    }

    function test_dispatch_encodesDataCorrectly() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(alice);
        aggregator.veto(proposalId);

        uint256 dispatchTime = block.timestamp;
        aggregator.dispatch(proposalId);

        IBridge.Message[] memory messages = bridge.getSentMessages();
        bytes memory msgData = messages[0].data;

        // message.data = abi.encodeCall(IMessageInvocable.onMessageInvocation, (vetoData))
        // Verify the expected encoding by rebuilding it
        bytes memory vetoData = abi.encode(proposalId, uint256(100 ether), dispatchTime);
        bytes memory expectedMsgData = abi.encodeCall(IMessageInvocable.onMessageInvocation, (vetoData));

        assertEq(keccak256(msgData), keccak256(expectedMsgData));
    }

    function test_dispatch_multipleDispatches() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(alice);
        aggregator.veto(proposalId);
        aggregator.dispatch(proposalId);

        // Bob votes then dispatch again
        vm.prank(bob);
        aggregator.veto(proposalId);
        aggregator.dispatch(proposalId);

        IBridge.Message[] memory messages = bridge.getSentMessages();
        assertEq(messages.length, 2);
    }

    function test_dispatch_permissionless() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(alice);
        aggregator.veto(proposalId);

        // Anyone can dispatch, even carol who has no tokens
        vm.prank(carol);
        aggregator.dispatch(proposalId);

        IBridge.Message[] memory messages = bridge.getSentMessages();
        assertEq(messages.length, 1);
    }

    function test_dispatch_justBeforeEndDate() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(alice);
        aggregator.veto(proposalId);

        // One second before endDate — should succeed
        vm.warp(END - 1);
        aggregator.dispatch(proposalId);

        IBridge.Message[] memory messages = bridge.getSentMessages();
        assertEq(messages.length, 1);
    }

    function test_dispatch_revert_feeTooLarge() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        vm.prank(alice);
        aggregator.veto(proposalId);

        uint256 tooMuch = uint256(type(uint64).max) + 1;
        vm.deal(address(this), tooMuch);

        vm.expectRevert(IL2VetoAggregator.FeeTooLarge.selector);
        aggregator.dispatch{value: tooMuch}(proposalId);
    }

    // =========================================================================
    // PARSE PROPOSAL ID TESTS
    // =========================================================================

    function test_parseProposalId_correctness() public view {
        uint256 proposalId = _makeProposalId();

        (uint64 counter, uint64 startDate, uint64 endDate, uint64 snapshotTimestamp) =
            aggregator.parseProposalId(proposalId);

        assertEq(counter, COUNTER);
        assertEq(startDate, START);
        assertEq(endDate, END);
        assertEq(snapshotTimestamp, SNAPSHOT);
    }

    function testFuzz_parseProposalId_roundtrip(
        uint64 snapshot,
        uint64 startDate,
        uint64 endDate,
        uint64 counter
    ) public view {
        uint256 proposalId = _makeProposalId(snapshot, startDate, endDate, counter);

        (uint64 c, uint64 s, uint64 e, uint64 snap) = aggregator.parseProposalId(proposalId);

        assertEq(c, counter);
        assertEq(s, startDate);
        assertEq(e, endDate);
        assertEq(snap, snapshot);
    }

    // =========================================================================
    // IS PROPOSAL OPEN TESTS
    // =========================================================================

    function test_isProposalOpen_duringPeriod() public {
        uint256 proposalId = _makeProposalId();

        vm.warp(START);
        assertTrue(aggregator.isProposalOpen(proposalId));

        vm.warp(START + 500);
        assertTrue(aggregator.isProposalOpen(proposalId));

        vm.warp(END - 1);
        assertTrue(aggregator.isProposalOpen(proposalId));
    }

    function test_isProposalOpen_beforeStart() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START - 1);
        assertFalse(aggregator.isProposalOpen(proposalId));
    }

    function test_isProposalOpen_atEnd() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(END);
        assertFalse(aggregator.isProposalOpen(proposalId));
    }

    function test_isProposalOpen_afterEnd() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(END + 100);
        assertFalse(aggregator.isProposalOpen(proposalId));
    }

    // =========================================================================
    // VIEW FUNCTION TESTS
    // =========================================================================

    function test_getVetoTally_returnsZeroForUnknown() public view {
        assertEq(aggregator.getVetoTally(999), 0);
    }

    function test_hasVetoed_returnsFalseForUnknown() public view {
        assertFalse(aggregator.hasVetoed(999, alice));
    }

    // =========================================================================
    // INTEGRATION: FULL VETO + DISPATCH FLOW
    // =========================================================================

    function test_integration_fullVetoAndDispatch() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        // Alice and Bob both veto
        vm.prank(alice);
        aggregator.veto(proposalId);

        vm.prank(bob);
        aggregator.veto(proposalId);

        // Verify accumulated tally
        assertEq(aggregator.getVetoTally(proposalId), 150 ether);

        // Anyone dispatches to L1
        aggregator.dispatch(proposalId);

        // Verify bridge message was sent
        IBridge.Message[] memory messages = bridge.getSentMessages();
        assertEq(messages.length, 1);

        IBridge.Message memory msg_ = messages[0];
        assertEq(msg_.to, l1Receiver);
        assertEq(msg_.destChainId, l1ChainId);
        assertEq(msg_.srcOwner, address(this));
        assertEq(msg_.destOwner, address(this));
        assertEq(msg_.value, 0);
    }

    function test_integration_vetoThenDispatchThenMoreVotesThenDispatch() public {
        uint256 proposalId = _makeProposalId();
        vm.warp(START);

        // First wave: Alice vetoes
        vm.prank(alice);
        aggregator.veto(proposalId);
        assertEq(aggregator.getVetoTally(proposalId), 100 ether);

        // First dispatch
        aggregator.dispatch(proposalId);

        // Second wave: Bob vetoes
        vm.warp(START + 100);
        vm.prank(bob);
        aggregator.veto(proposalId);
        assertEq(aggregator.getVetoTally(proposalId), 150 ether);

        // Second dispatch with updated tally
        aggregator.dispatch(proposalId);

        IBridge.Message[] memory messages = bridge.getSentMessages();
        assertEq(messages.length, 2);
    }

    // =========================================================================
    // FUZZ TESTS
    // =========================================================================

    function testFuzz_constructor_validParams(address _bridge, uint64 _chainId, address _token, address _l1Receiver) public {
        vm.assume(_bridge != address(0));
        vm.assume(_chainId > 0);
        vm.assume(_token != address(0));
        vm.assume(_l1Receiver != address(0));

        L2VetoAggregator a = new L2VetoAggregator(_bridge, _chainId, _token, _l1Receiver);

        assertEq(a.bridge(), _bridge);
        assertEq(a.l1ChainId(), _chainId);
        assertEq(address(a.votingToken()), _token);
        assertEq(a.l1Receiver(), _l1Receiver);
    }

}
