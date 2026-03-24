// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {HandlerBase} from "../base/HandlerBase.sol";
import {InvariantTestBase} from "../base/InvariantTestBase.sol";
import {OptimisticTokenVotingPlugin} from "../../../src/OptimisticTokenVotingPlugin.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

contract ProposalHandler is HandlerBase {
    InvariantTestBase internal base;
    OptimisticTokenVotingPlugin internal plugin;
    address internal proposer;

    uint256 public createCount;
    uint256 public createFailCount;
    uint256 public emergencyCount;

    constructor(address _testBase) HandlerBase(_testBase) {
        base = InvariantTestBase(_testBase);
        plugin = base.plugin();
        proposer = base.PROPOSER();
    }

    function createProposal(uint256 seed) external {
        // governanceSettings returns (minVetoRatio, minDuration, timelockPeriod, l2InactivityPeriod, l2AggregationGracePeriod, skipL2)
        (, uint32 minDuration,,,,) = plugin.governanceSettings();

        // 5% chance of emergency proposal (duration=0, auto-executed)
        bool emergency = seed % 20 == 0;
        uint64 duration =
            emergency ? 0 : uint64(bound(seed, minDuration, uint256(minDuration) + 10 days));

        IDAO.Action[] memory actions = new IDAO.Action[](0);

        vm.prank(proposer);
        try plugin.createProposal("", actions, 0, duration) returns (uint256 proposalId) {
            createCount++;
            base.pushActiveProposalId(proposalId);
            base.setProposalCreatedAt(proposalId, block.timestamp);

            if (emergency) {
                // Emergency proposals are auto-executed by the plugin
                emergencyCount++;
                base.setProposalExecuted(proposalId);
                base.incrementExecutionCount();
            }
        } catch {
            createFailCount++;
        }
    }

    function printHandlerStatistics() public view override {
        _printSection("PROPOSAL HANDLER");
        _printStat("Proposals created", createCount);
        _printStat("Emergency proposals", emergencyCount);
        _printStat("Create failures", createFailCount);
    }
}
