// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {InvariantTestBase} from "./base/InvariantTestBase.sol";

contract CrosschainFlowInvariants is InvariantTestBase {
    /// @notice receiver.getL2VetoTally(id) >= ghost_l2VetoTally (plugin's accepted L2 balance)
    /// @dev The receiver may store a higher tally if submitL2Vetoes to the plugin failed
    function invariant_ReceiverTallyAtLeastPluginAccepted() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            uint256 receiverTally = receiver.getL2VetoTally(id);
            uint256 pluginAcceptedL2 = ghost_l2VetoTally[id];

            assertGe(
                receiverTally,
                pluginAcceptedL2,
                string.concat("ReceiverTallyBelowPluginAccepted for proposal ", vm.toString(id))
            );
        }
    }

    /// @notice receiver.getL2DispatchTimestamp(id) never decreases
    function invariant_DispatchTimestampMonotonicity() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            uint256 receiverTimestamp = receiver.getL2DispatchTimestamp(id);
            uint256 ghostTimestamp = ghost_lastDispatchTimestamp[id];

            assertGe(
                receiverTimestamp,
                ghostTimestamp,
                string.concat("DispatchTimestampDecreased for proposal ", vm.toString(id))
            );
        }
    }

}
