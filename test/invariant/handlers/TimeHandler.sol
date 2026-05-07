// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {HandlerBase} from "../base/HandlerBase.sol";
import {InvariantTestBase} from "../base/InvariantTestBase.sol";
import {OptimisticTokenVotingPlugin} from "../../../src/OptimisticTokenVotingPlugin.sol";

contract TimeHandler is HandlerBase {
    InvariantTestBase internal base;
    OptimisticTokenVotingPlugin internal plugin;

    uint256 public advanceCount;
    uint256 public jumpCount;

    uint256 constant MAX_TIME_JUMP = 15 days;

    constructor(address _testBase) HandlerBase(_testBase) {
        base = InvariantTestBase(_testBase);
        plugin = base.plugin();
    }

    function advanceTime(uint256 seed) external {
        uint256 jump = bound(seed, 1, MAX_TIME_JUMP);
        vm.warp(block.timestamp + jump);
        vm.roll(block.number + jump / 12);
        advanceCount++;
    }

    function jumpToPhase(uint256 proposalSeed, uint256 phaseSeed) external {
        uint256 proposalCount = base.getActiveProposalCount();
        if (proposalCount == 0) return;

        uint256 proposalId = base.ghost_activeProposalIds(proposalSeed % proposalCount);

        (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);

        if (params.snapshotTimestamp == 0) return;

        // governanceSettings returns (minVetoRatio, minDuration, timelockPeriod, l2InactivityPeriod, l2AggregationGracePeriod, skipL2)
        (,, uint32 timelockPeriod,, uint32 l2AggregationGracePeriod,) = plugin.governanceSettings();

        uint256 phase = phaseSeed % 5;
        uint256 targetTime;

        if (phase == 0) {
            // Mid veto period
            targetTime = (uint256(params.vetoStartDate) + uint256(params.vetoEndDate)) / 2;
        } else if (phase == 1) {
            // Just after veto end
            targetTime = uint256(params.vetoEndDate) + 1;
        } else if (phase == 2) {
            // Just after L2 aggregation grace period ends
            targetTime = uint256(params.vetoEndDate) + uint256(l2AggregationGracePeriod) + 1;
        } else if (phase == 3) {
            // Just after timelock ends (executable)
            targetTime = uint256(params.vetoEndDate) + uint256(timelockPeriod) + 1;
        } else {
            // Well past executable
            targetTime = uint256(params.vetoEndDate) + uint256(timelockPeriod) + 1 days;
        }

        // Only warp forward
        if (targetTime > block.timestamp) {
            uint256 delta = targetTime - block.timestamp;
            vm.warp(targetTime);
            vm.roll(block.number + delta / 12);
            jumpCount++;
        }
    }

    function printHandlerStatistics() public view override {
        _printSection("TIME HANDLER");
        _printStat("Time advances", advanceCount);
        _printStat("Phase jumps", jumpCount);
        _printStat("Current timestamp", block.timestamp);
    }
}
