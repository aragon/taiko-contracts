// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {InvariantTestBase} from "./base/InvariantTestBase.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";

contract ProposalLifecycleInvariants is InvariantTestBase {
    /// @notice Once executed, a proposal stays executed
    function invariant_ExecutedProposalStaysExecuted() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            if (ghost_proposalExecuted[id]) {
                (, bool executed,,,,,) = plugin.getProposal(id);
                assertTrue(
                    executed,
                    string.concat("ExecutedProposalStaysExecuted failed for ", vm.toString(id))
                );
            }
        }
    }

    /// @notice If veto threshold is reached, canExecute must be false
    function invariant_CannotExecuteWithVetoThresholdReached() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            if (plugin.isMinVetoRatioReached(id)) {
                assertFalse(
                    plugin.canExecute(id),
                    string.concat("CannotExecuteWithVetoThreshold failed for ", vm.toString(id))
                );
            }
        }
    }

    /// @notice During veto period, canExecute must be false
    function invariant_CannotExecuteDuringVetoPeriod() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) = plugin.getProposal(id);

            if (params.snapshotTimestamp == 0) continue;

            if (block.timestamp < params.vetoEndDate) {
                assertFalse(
                    plugin.canExecute(id),
                    string.concat("CannotExecuteDuringVetoPeriod failed for ", vm.toString(id))
                );
            }
        }
    }

    /// @notice During exit window (timelock), canExecute must be false
    function invariant_CannotExecuteDuringExitWindow() public view {
        // governanceSettings returns (minVetoRatio, minDuration, timelockPeriod, l2InactivityPeriod, l2AggregationGracePeriod, skipL2)
        (,, uint32 timelockPeriod,,,) = plugin.governanceSettings();

        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) = plugin.getProposal(id);

            if (params.snapshotTimestamp == 0) continue;

            uint256 exitWindowEnd = uint256(params.vetoEndDate) + uint256(timelockPeriod);

            if (block.timestamp >= params.vetoEndDate && block.timestamp < exitWindowEnd) {
                assertFalse(
                    plugin.canExecute(id),
                    string.concat("CannotExecuteDuringExitWindow failed for ", vm.toString(id))
                );
            }
        }
    }

    /// @notice Proposals with unavailableL2 should never have L2 veto contributions
    function invariant_UnavailableL2ProposalsHaveNoL2Vetoes() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            (,, OptimisticTokenVotingPlugin.ProposalParameters memory params, uint256 vetoTally,,,) =
                plugin.getProposal(id);

            if (params.snapshotTimestamp == 0) continue;

            if (params.unavailableL2) {
                // vetoTally should equal only L1 contributions (no L2 component)
                assertEq(
                    vetoTally,
                    ghost_l1VetoTally[id],
                    string.concat("UnavailableL2 proposal has L2 vetoes for ", vm.toString(id))
                );
            }
        }
    }

    /// @notice After veto period ends, canVeto must be false for all voters
    function invariant_CannotVetoAfterEnd() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            (,, OptimisticTokenVotingPlugin.ProposalParameters memory params,,,,) = plugin.getProposal(id);

            if (params.snapshotTimestamp == 0) continue;

            if (block.timestamp >= params.vetoEndDate) {
                for (uint256 j = 0; j < allVoters.length; j++) {
                    assertFalse(
                        plugin.canVeto(id, allVoters[j]),
                        string.concat(
                            "CannotVetoAfterEnd failed for voter ",
                            vm.toString(allVoters[j]),
                            " on proposal ",
                            vm.toString(id)
                        )
                    );
                }
            }
        }
    }
}
