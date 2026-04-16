// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {InvariantTestSetup} from "./InvariantTestSetup.sol";
import {console2 as console} from "forge-std/console2.sol";

import {ProposalHandler} from "../handlers/ProposalHandler.sol";
import {L1VetoHandler} from "../handlers/L1VetoHandler.sol";
import {L2VetoHandler} from "../handlers/L2VetoHandler.sol";
import {BridgeHandler} from "../handlers/BridgeHandler.sol";
import {TimeHandler} from "../handlers/TimeHandler.sol";
import {ExecutionHandler} from "../handlers/ExecutionHandler.sol";

abstract contract InvariantTestBase is InvariantTestSetup {
    // =========================================================================
    // HANDLERS
    // =========================================================================

    struct Handlers {
        ProposalHandler proposal;
        L1VetoHandler l1Veto;
        L2VetoHandler l2Veto;
        BridgeHandler bridge;
        TimeHandler time;
        ExecutionHandler execution;
    }

    Handlers public allHandlers;
    address[] public handlers;

    // =========================================================================
    // GHOST VARIABLES — Veto Tracking
    // =========================================================================

    mapping(uint256 => uint256) public ghost_l1VetoTally;
    mapping(uint256 => uint256) public ghost_l2VetoTally;
    mapping(uint256 => mapping(address => bool)) public ghost_hasVetoedL1;
    mapping(uint256 => mapping(address => bool)) public ghost_hasVetoedL2;
    mapping(uint256 => uint256) public ghost_l2AggregatorTally;
    mapping(uint256 => uint256) public ghost_previousL2VetoTally;

    // =========================================================================
    // GHOST VARIABLES — Proposal Tracking
    // =========================================================================

    uint256[] public ghost_activeProposalIds;
    mapping(uint256 => bool) public ghost_proposalExecuted;
    mapping(uint256 => uint256) public ghost_proposalCreatedAt;

    // =========================================================================
    // GHOST VARIABLES — Bridge Tracking
    // =========================================================================

    mapping(uint256 => bool) public ghost_deliveredMessageIndices;
    mapping(uint256 => uint256) public ghost_lastDispatchTimestamp;

    // =========================================================================
    // GHOST VARIABLES — Counters
    // =========================================================================

    uint256 public ghost_l1VetoCount;
    uint256 public ghost_l2VetoCount;
    uint256 public ghost_dispatchCount;
    uint256 public ghost_deliveryCount;
    uint256 public ghost_executionCount;

    // =========================================================================
    // GHOST VARIABLE SETTERS (called by handlers)
    // =========================================================================

    function pushActiveProposalId(uint256 id) external {
        ghost_activeProposalIds.push(id);
    }

    function setProposalCreatedAt(uint256 id, uint256 ts) external {
        ghost_proposalCreatedAt[id] = ts;
    }

    function setProposalExecuted(uint256 id) external {
        ghost_proposalExecuted[id] = true;
    }

    function incrementL1VetoTally(uint256 id, uint256 amount) external {
        ghost_l1VetoTally[id] += amount;
    }

    function setHasVetoedL1(uint256 id, address voter) external {
        ghost_hasVetoedL1[id][voter] = true;
    }

    function incrementL2AggregatorTally(uint256 id, uint256 amount) external {
        ghost_l2AggregatorTally[id] += amount;
    }

    function setHasVetoedL2(uint256 id, address voter) external {
        ghost_hasVetoedL2[id][voter] = true;
    }

    function setL2VetoTally(uint256 id, uint256 tally) external {
        ghost_previousL2VetoTally[id] = ghost_l2VetoTally[id];
        ghost_l2VetoTally[id] = tally;
    }

    function setLastDispatchTimestamp(uint256 id, uint256 ts) external {
        ghost_lastDispatchTimestamp[id] = ts;
    }

    function setDeliveredMessageIndex(uint256 index) external {
        ghost_deliveredMessageIndices[index] = true;
    }

    function incrementL1VetoCount() external {
        ghost_l1VetoCount++;
    }

    function incrementL2VetoCount() external {
        ghost_l2VetoCount++;
    }

    function incrementDispatchCount() external {
        ghost_dispatchCount++;
    }

    function incrementDeliveryCount() external {
        ghost_deliveryCount++;
    }

    function incrementExecutionCount() external {
        ghost_executionCount++;
    }

    // =========================================================================
    // GHOST VARIABLE GETTERS (for handlers/invariants)
    // =========================================================================

    function getActiveProposalIds() external view returns (uint256[] memory) {
        return ghost_activeProposalIds;
    }

    function getActiveProposalCount() external view returns (uint256) {
        return ghost_activeProposalIds.length;
    }

    // =========================================================================
    // SETUP
    // =========================================================================

    function setUp() public virtual override {
        super.setUp();

        _initializeHandlers();
        _configureInvariantTargets();
    }

    function _initializeHandlers() internal {
        allHandlers = Handlers({
            proposal: new ProposalHandler(address(this)),
            l1Veto: new L1VetoHandler(address(this)),
            l2Veto: new L2VetoHandler(address(this)),
            bridge: new BridgeHandler(address(this)),
            time: new TimeHandler(address(this)),
            execution: new ExecutionHandler(address(this))
        });

        handlers.push(address(allHandlers.proposal));
        handlers.push(address(allHandlers.l1Veto));
        handlers.push(address(allHandlers.l2Veto));
        handlers.push(address(allHandlers.bridge));
        handlers.push(address(allHandlers.time));
        handlers.push(address(allHandlers.execution));
    }

    function _configureInvariantTargets() internal virtual {
        for (uint256 i = 0; i < handlers.length; i++) {
            targetContract(handlers[i]);
        }

        // Exclude system contracts from being directly targeted
        excludeContract(address(dao));
        excludeContract(address(plugin));
        excludeContract(address(aggregator));
        excludeContract(address(receiver));
        excludeContract(address(bridgeMock));
        excludeContract(address(votingToken));
    }

    // =========================================================================
    // AFTER INVARIANT (stats printing)
    // =========================================================================

    function afterInvariant() public view {
        console.log("");
        console.log("========================================");
        console.log("         HANDLER STATISTICS             ");
        console.log("========================================");

        allHandlers.proposal.printHandlerStatistics();
        allHandlers.l1Veto.printHandlerStatistics();
        allHandlers.l2Veto.printHandlerStatistics();
        allHandlers.bridge.printHandlerStatistics();
        allHandlers.time.printHandlerStatistics();
        allHandlers.execution.printHandlerStatistics();

        console.log("");
        console.log("========================================");
        console.log("        GHOST VARIABLES SUMMARY         ");
        console.log("========================================");
        console.log("  Active proposals:", ghost_activeProposalIds.length);
        console.log("  L1 veto count:  ", ghost_l1VetoCount);
        console.log("  L2 veto count:  ", ghost_l2VetoCount);
        console.log("  Dispatches:     ", ghost_dispatchCount);
        console.log("  Deliveries:     ", ghost_deliveryCount);
        console.log("  Executions:     ", ghost_executionCount);
        console.log("========================================");
        console.log("");
    }
}
