// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {HandlerBase} from "../base/HandlerBase.sol";
import {InvariantTestBase} from "../base/InvariantTestBase.sol";
import {OptimisticTokenVotingPlugin} from "../../../src/OptimisticTokenVotingPlugin.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract L1VetoHandler is HandlerBase {
    InvariantTestBase internal base;
    OptimisticTokenVotingPlugin internal plugin;
    IVotesUpgradeable internal votingToken;

    uint256 public vetoCount;
    uint256 public vetoSkipCount;

    constructor(address _testBase) HandlerBase(_testBase) {
        base = InvariantTestBase(_testBase);
        plugin = base.plugin();
        votingToken = IVotesUpgradeable(address(base.votingToken()));
    }

    function vetoOnL1(uint256 voterSeed, uint256 proposalSeed) external {
        uint256 proposalCount = base.getActiveProposalCount();
        if (proposalCount == 0) return;

        address voter = base.l1Voters(voterSeed % base.NUM_L1_VOTERS());
        uint256 proposalId = base.ghost_activeProposalIds(proposalSeed % proposalCount);

        if (!plugin.canVeto(proposalId, voter)) {
            vetoSkipCount++;
            return;
        }

        // Get voting power for ghost variable update
        (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        uint256 votingPower = votingToken.getPastVotes(voter, params.snapshotTimestamp);

        vm.prank(voter);
        plugin.veto(proposalId);

        vetoCount++;
        base.incrementL1VetoTally(proposalId, votingPower);
        base.setHasVetoedL1(proposalId, voter);
        base.incrementL1VetoCount();
    }

    function printHandlerStatistics() public view override {
        _printSection("L1 VETO HANDLER");
        _printStat("Vetoes cast", vetoCount);
        _printStat("Vetoes skipped", vetoSkipCount);
    }
}
