// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {HandlerBase} from "../base/HandlerBase.sol";
import {InvariantTestBase} from "../base/InvariantTestBase.sol";
import {L2VetoAggregator} from "../../../src/crosschain/L2VetoAggregator.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract L2VetoHandler is HandlerBase {
    InvariantTestBase internal base;
    L2VetoAggregator internal aggregator;
    IVotesUpgradeable internal votingToken;

    uint256 public vetoCount;
    uint256 public vetoSkipCount;

    constructor(address _testBase) HandlerBase(_testBase) {
        base = InvariantTestBase(_testBase);
        aggregator = base.aggregator();
        votingToken = IVotesUpgradeable(address(base.votingToken()));
    }

    function vetoOnL2(uint256 voterSeed, uint256 proposalSeed) external {
        uint256 proposalCount = base.getActiveProposalCount();
        if (proposalCount == 0) return;

        address voter = base.l2Voters(voterSeed % base.NUM_L2_VOTERS());
        uint256 proposalId = base.ghost_activeProposalIds(proposalSeed % proposalCount);

        if (!aggregator.canVeto(proposalId, voter)) {
            vetoSkipCount++;
            return;
        }

        // parseProposalId returns (counter, startDate, endDate, snapshotTimestamp)
        (,,, uint64 snapshotTimestamp) = aggregator.parseProposalId(proposalId);
        uint256 votingPower = votingToken.getPastVotes(voter, snapshotTimestamp);

        vm.prank(voter);
        aggregator.veto(proposalId);

        vetoCount++;
        base.incrementL2AggregatorTally(proposalId, votingPower);
        base.setHasVetoedL2(proposalId, voter);
        base.incrementL2VetoCount();
    }

    function printHandlerStatistics() public view override {
        _printSection("L2 VETO HANDLER");
        _printStat("Vetoes cast", vetoCount);
        _printStat("Vetoes skipped", vetoSkipCount);
    }
}
