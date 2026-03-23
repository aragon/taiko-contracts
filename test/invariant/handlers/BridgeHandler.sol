// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {HandlerBase} from "../base/HandlerBase.sol";
import {InvariantTestBase} from "../base/InvariantTestBase.sol";
import {L2VetoAggregator} from "../../../src/crosschain/L2VetoAggregator.sol";
import {L2VetoReceiver} from "../../../src/crosschain/L2VetoReceiver.sol";
import {TaikoBridgeMock} from "../../mocks/TaikoBridgeMock.sol";
import {IBridge} from "../../../src/interfaces/IBridge.sol";

contract BridgeHandler is HandlerBase {
    InvariantTestBase internal base;
    L2VetoAggregator internal aggregator;
    L2VetoReceiver internal receiver;
    TaikoBridgeMock internal bridgeMock;
    uint64 internal constant L2_CHAIN_ID = 167000;

    uint256 public dispatchCount;
    uint256 public dispatchFailCount;
    uint256 public deliveryCount;
    uint256 public deliveryFailCount;
    uint256 public deliverySkipCount;

    constructor(address _testBase) HandlerBase(_testBase) {
        base = InvariantTestBase(_testBase);
        aggregator = base.aggregator();
        receiver = base.receiver();
        bridgeMock = base.bridgeMock();
    }

    function dispatchFromL2(uint256 proposalSeed) external {
        uint256 proposalCount = base.getActiveProposalCount();
        if (proposalCount == 0) return;

        uint256 proposalId = base.ghost_activeProposalIds(proposalSeed % proposalCount);

        // Simulate L2 chain ID so bridge mock records correct srcChainId
        vm.chainId(L2_CHAIN_ID);

        try aggregator.dispatch(proposalId) {
            dispatchCount++;
            base.incrementDispatchCount();
        } catch {
            dispatchFailCount++;
        }

        // Restore to default chain ID
        vm.chainId(31337);
    }

    function deliverToL1(uint256 messageSeed) external {
        uint64 totalMessages = bridgeMock.nextMessageId();
        if (totalMessages == 0) {
            deliverySkipCount++;
            return;
        }

        // Find undelivered messages
        uint256[] memory undelivered = new uint256[](totalMessages);
        uint256 count;
        for (uint256 i = 0; i < totalMessages; i++) {
            if (!base.ghost_deliveredMessageIndices(i)) {
                undelivered[count++] = i;
            }
        }

        if (count == 0) {
            deliverySkipCount++;
            return;
        }

        // Pick random undelivered message
        uint256 idx = undelivered[messageSeed % count];

        // Get the full message using getSentMessages helper
        IBridge.Message[] memory allMessages = bridgeMock.getSentMessages();
        IBridge.Message memory message = allMessages[idx];

        // Decode the inner data to extract proposalId BEFORE delivery
        bytes memory innerData = abi.decode(_stripSelector(message.data), (bytes));
        (uint256 proposalId,, uint256 dispatchedAt) = abi.decode(innerData, (uint256, uint256, uint256));

        // Read plugin vetoTally BEFORE delivery
        (,,, uint256 prevPluginVetoTally,,,) = base.plugin().getProposal(proposalId);

        // processMessage sets context and calls the target
        try bridgeMock.processMessage(message, "") returns (IBridge.Status status, IBridge.StatusReason) {
            base.setDeliveredMessageIndex(idx);

            if (status == IBridge.Status.DONE) {
                deliveryCount++;
                base.incrementDeliveryCount();

                // Update receiver-related ghosts
                uint256 receiverTimestamp = receiver.getL2DispatchTimestamp(proposalId);
                if (receiverTimestamp == dispatchedAt) {
                    base.setLastDispatchTimestamp(proposalId, dispatchedAt);
                }

                // Only update ghost_l2VetoTally if plugin actually accepted the L2 vetoes
                // (detect by comparing plugin's vetoTally before and after)
                (,,, uint256 newPluginVetoTally,,,) = base.plugin().getProposal(proposalId);
                if (newPluginVetoTally != prevPluginVetoTally) {
                    // Plugin accepted: aggregatedL2Balance = newVetoTally - ghost_l1VetoTally
                    uint256 l2Balance = newPluginVetoTally - base.ghost_l1VetoTally(proposalId);
                    base.setL2VetoTally(proposalId, l2Balance);
                }
            } else {
                deliveryFailCount++;
            }
        } catch {
            deliveryFailCount++;
        }
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory) {
        require(data.length >= 4, "data too short");
        bytes memory result = new bytes(data.length - 4);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = data[i + 4];
        }
        return result;
    }

    function printHandlerStatistics() public view override {
        _printSection("BRIDGE HANDLER");
        _printStat("Dispatches", dispatchCount);
        _printStat("Dispatch failures", dispatchFailCount);
        _printStat("Deliveries", deliveryCount);
        _printStat("Delivery failures", deliveryFailCount);
        _printStat("Delivery skips", deliverySkipCount);
        _printStat("Pending messages", _pendingCount());
    }

    function _pendingCount() internal view returns (uint256) {
        uint64 total = bridgeMock.nextMessageId();
        uint256 delivered;
        for (uint256 i = 0; i < total; i++) {
            if (base.ghost_deliveredMessageIndices(i)) delivered++;
        }
        return total - delivered;
    }
}
