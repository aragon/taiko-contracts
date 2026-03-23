// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {InvariantTestBase} from "./base/InvariantTestBase.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";

contract VetoTallyInvariants is InvariantTestBase {
    /// @notice plugin.vetoTally == ghost_l1VetoTally + ghost_l2VetoTally
    function invariant_L1TallyConsistency() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            (,, OptimisticTokenVotingPlugin.ProposalParameters memory params, uint256 vetoTally,,,) =
                plugin.getProposal(id);

            if (params.snapshotTimestamp == 0) continue;

            uint256 expected = ghost_l1VetoTally[id] + ghost_l2VetoTally[id];

            assertEq(
                vetoTally, expected, string.concat("L1TallyConsistency failed for proposal ", vm.toString(id))
            );
        }
    }

    /// @notice plugin.aggregatedL2Balance never decreases
    function invariant_L2TallyMonotonicity() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            (,, OptimisticTokenVotingPlugin.ProposalParameters memory params, uint256 vetoTally,,,) =
                plugin.getProposal(id);

            if (params.snapshotTimestamp == 0) continue;

            // aggregatedL2Balance = vetoTally - ghost_l1VetoTally[id]
            uint256 actualL2Balance = vetoTally - ghost_l1VetoTally[id];

            assertGe(
                actualL2Balance,
                ghost_l2VetoTally[id],
                string.concat("L2TallyMonotonicity failed for proposal ", vm.toString(id))
            );
        }
    }

    /// @notice aggregator.getVetoTally(id) == ghost_l2AggregatorTally[id]
    function invariant_L2AggregatorTallyAccumulation() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            uint256 actualTally = aggregator.getVetoTally(id);
            uint256 ghostTally = ghost_l2AggregatorTally[id];

            assertEq(
                actualTally,
                ghostTally,
                string.concat("L2AggregatorTallyAccumulation failed for proposal ", vm.toString(id))
            );
        }
    }

    /// @notice ghost_hasVetoedL1 matches plugin.hasVetoed for all voters
    function invariant_NoDoubleVetoL1() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            for (uint256 j = 0; j < allVoters.length; j++) {
                address voter = allVoters[j];
                bool ghostVetoed = ghost_hasVetoedL1[id][voter];
                bool actualVetoed = plugin.hasVetoed(id, voter);

                assertEq(
                    ghostVetoed,
                    actualVetoed,
                    string.concat(
                        "NoDoubleVetoL1 mismatch for voter ",
                        vm.toString(voter),
                        " on proposal ",
                        vm.toString(id)
                    )
                );
            }
        }
    }

    /// @notice ghost_hasVetoedL2 matches aggregator.hasVetoed for all L2 voters
    function invariant_NoDoubleVetoL2() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            for (uint256 j = 0; j < l2Voters.length; j++) {
                address voter = l2Voters[j];
                bool ghostVetoed = ghost_hasVetoedL2[id][voter];
                bool actualVetoed = aggregator.hasVetoed(id, voter);

                assertEq(
                    ghostVetoed,
                    actualVetoed,
                    string.concat(
                        "NoDoubleVetoL2 mismatch for voter ",
                        vm.toString(voter),
                        " on proposal ",
                        vm.toString(id)
                    )
                );
            }
        }
    }

    /// @notice vetoTally never exceeds total voting supply at snapshot
    function invariant_VetoTallyNeverExceedsTotalSupply() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            (,, OptimisticTokenVotingPlugin.ProposalParameters memory params, uint256 vetoTally,,,) =
                plugin.getProposal(id);

            if (params.snapshotTimestamp == 0) continue;

            uint256 totalSupply = votingToken.getPastTotalSupply(params.snapshotTimestamp);

            assertLe(
                vetoTally,
                totalSupply,
                string.concat("VetoTallyExceedsTotalSupply for proposal ", vm.toString(id))
            );
        }
    }
}
