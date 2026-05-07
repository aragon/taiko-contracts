// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {HandlerBase} from "../base/HandlerBase.sol";
import {InvariantTestBase} from "../base/InvariantTestBase.sol";
import {OptimisticTokenVotingPlugin} from "../../../src/OptimisticTokenVotingPlugin.sol";

contract ExecutionHandler is HandlerBase {
    InvariantTestBase internal base;
    OptimisticTokenVotingPlugin internal plugin;

    uint256 public executeCount;
    uint256 public executeSkipCount;

    constructor(address _testBase) HandlerBase(_testBase) {
        base = InvariantTestBase(_testBase);
        plugin = base.plugin();
    }

    function tryExecute(uint256 proposalSeed) external {
        uint256 proposalCount = base.getActiveProposalCount();
        if (proposalCount == 0) return;

        uint256 proposalId = base.ghost_activeProposalIds(proposalSeed % proposalCount);

        if (base.ghost_proposalExecuted(proposalId)) {
            executeSkipCount++;
            return;
        }

        if (!plugin.canExecute(proposalId)) {
            executeSkipCount++;
            return;
        }

        try plugin.execute(proposalId) {
            executeCount++;
            base.setProposalExecuted(proposalId);
            base.incrementExecutionCount();
        } catch {
            executeSkipCount++;
        }
    }

    function printHandlerStatistics() public view override {
        _printSection("EXECUTION HANDLER");
        _printStat("Executions", executeCount);
        _printStat("Skips", executeSkipCount);
    }
}
