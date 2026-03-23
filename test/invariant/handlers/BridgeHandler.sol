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

        try aggregator.dispatch(proposalId) {
            dispatchCount++;
            base.incrementDispatchCount();
        } catch {
            dispatchFailCount++;
        }
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

        // processMessage sets context and calls the target
        try bridgeMock.processMessage(message, "") returns (IBridge.Status status, IBridge.StatusReason) {
            base.setDeliveredMessageIndex(idx);

            if (status == IBridge.Status.DONE) {
                deliveryCount++;
                base.incrementDeliveryCount();

                // Decode the inner data to extract proposalId
                // message.data = abi.encodeCall(IMessageInvocable.onMessageInvocation, (innerData))
                // innerData = abi.encode(proposalId, vetoTally, dispatchedAt)
                bytes memory innerData = abi.decode(_stripSelector(message.data), (bytes));
                (uint256 proposalId,, uint256 dispatchedAt) =
                    abi.decode(innerData, (uint256, uint256, uint256));

                // Update ghosts based on what the receiver actually stored
                uint256 receiverTimestamp = receiver.getL2DispatchTimestamp(proposalId);

                if (receiverTimestamp == dispatchedAt) {
                    uint256 receiverTally = receiver.getL2VetoTally(proposalId);
                    base.setL2VetoTally(proposalId, receiverTally);
                    base.setLastDispatchTimestamp(proposalId, dispatchedAt);
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
