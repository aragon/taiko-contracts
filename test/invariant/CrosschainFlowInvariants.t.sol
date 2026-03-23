// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {InvariantTestBase} from "./base/InvariantTestBase.sol";

contract CrosschainFlowInvariants is InvariantTestBase {
    /// @notice receiver.getL2VetoTally(id) matches our tracked ghost_l2VetoTally
    function invariant_ReceiverTallyMatchesLastDelivery() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            uint256 receiverTally = receiver.getL2VetoTally(id);
            uint256 ghostTally = ghost_l2VetoTally[id];

            if (ghostTally > 0) {
                assertEq(
                    receiverTally,
                    ghostTally,
                    string.concat("ReceiverTallyMismatch for proposal ", vm.toString(id))
                );
            }
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

    /// @notice The ERC20Vault (bridge) address can never veto directly on the plugin
    function invariant_BridgeVaultCannotVetoDirectly() public view {
        for (uint256 i = 0; i < ghost_activeProposalIds.length; i++) {
            uint256 id = ghost_activeProposalIds[i];

            assertFalse(
                plugin.canVeto(id, TAIKO_ERC20_VAULT),
                string.concat("BridgeVaultCanVeto for proposal ", vm.toString(id))
            );
        }
    }
}
