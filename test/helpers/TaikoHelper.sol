// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, Vm} from "forge-std/Test.sol";
import {IBridge} from "../../src/interfaces/IBridge.sol";

/// @title TaikoHelper
/// @notice Foundry helper to simulate Taiko L2->L1 message relay in fork tests
/// @dev Follows the pigeon pattern (https://github.com/exp-table/pigeon)
///
/// Usage:
/// ```solidity
/// // On L2 fork - send message
/// vm.selectFork(l2Fork);
/// vm.recordLogs();
/// sender.sendFunctionCall{value: 0.01 ether}(selector, args);
/// Vm.Log[] memory logs = vm.getRecordedLogs();
///
/// // Simulate relay to L1
/// taikoHelper.relay(L2_BRIDGE, L1_BRIDGE, l1Fork, logs);
///
/// // Verify on L1
/// vm.selectFork(l1Fork);
/// assertEq(receiver.storedValue(), expectedValue);
/// ```
contract TaikoHelper is Test {
    /// @dev MessageSent event selector: keccak256("MessageSent(bytes32,(uint64,uint64,uint32,address,uint64,address,uint64,address,address,uint256,bytes))")
    bytes32 public constant MESSAGE_SENT_SELECTOR =
        0xe33fd33b4f45b95b1c196242240c5b5233129d724b578f95b66ce8d8aae93517;

    /// @notice Emitted when a message is simulated on the destination chain
    event MessageRelayed(
        bytes32 indexed msgHash,
        address indexed from,
        address indexed to,
        uint64 srcChainId,
        bool success
    );

    /// @notice Simulates relaying all MessageSent events from L2 to L1
    /// @param l2Bridge The L2 bridge address (source of events)
    /// @param l1Bridge The L1 bridge address (to impersonate)
    /// @param l1ForkId The Foundry fork ID for L1
    /// @param logs The recorded logs containing MessageSent events
    function relay(address l2Bridge, address l1Bridge, uint256 l1ForkId, Vm.Log[] calldata logs) external {
        _relay(l2Bridge, l1Bridge, l1ForkId, logs, false);
    }

    /// @notice Simulates relaying with detailed logging
    function relayWithLogs(
        address l2Bridge,
        address l1Bridge,
        uint256 l1ForkId,
        Vm.Log[] calldata logs
    ) external {
        _relay(l2Bridge, l1Bridge, l1ForkId, logs, true);
    }

    /// @notice Simulates relaying a single message
    function relaySingleMessage(address l1Bridge, uint256 l1ForkId, IBridge.Message calldata message) external {
        _trySelectFork(l1ForkId);
        bytes32 msgHash = _hashMessage(message);
        _simulateMessageDelivery(l1Bridge, message, msgHash, true);
    }

    /// @notice Simulates relaying a single message in local mode (no forks)
    function relayMessageLocal(address l1Bridge, IBridge.Message calldata message) external {
        bytes32 msgHash = _hashMessage(message);
        _simulateMessageDelivery(l1Bridge, message, msgHash, true);
    }

    /// @notice Internal relay implementation
    function _relay(
        address l2Bridge,
        address l1Bridge,
        uint256 l1ForkId,
        Vm.Log[] calldata logs,
        bool verbose
    ) internal {
        uint256 currentFork = vm.activeFork();
        uint256 messagesProcessed = 0;

        vm.selectFork(l1ForkId);

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == l2Bridge && logs[i].topics[0] == MESSAGE_SENT_SELECTOR) {
                bytes32 msgHash = logs[i].topics[1];
                IBridge.Message memory message = _decodeMessageFromLog(logs[i].data);
                _simulateMessageDelivery(l1Bridge, message, msgHash, verbose);
                messagesProcessed++;
            }
        }

        if (verbose) {
            emit log_named_uint("Messages relayed", messagesProcessed);
        }

        vm.selectFork(currentFork);
    }

    /// @notice Decodes a Message struct from MessageSent event data
    function _decodeMessageFromLog(bytes memory data) internal pure returns (IBridge.Message memory message) {
        bytes memory structData = _slice(data, 32, data.length - 32);
        message = _decodeMessageStruct(structData);
    }

    /// @notice Helper to decode Message struct
    function _decodeMessageStruct(bytes memory data) internal pure returns (IBridge.Message memory) {
        uint64 id = uint64(bytes8(_extractBytes(data, 24, 8)));
        uint64 fee = uint64(bytes8(_extractBytes(data, 56, 8)));
        uint32 gasLimit = uint32(bytes4(_extractBytes(data, 92, 4)));
        address from = address(bytes20(_extractBytes(data, 108, 20)));
        uint64 srcChainId = uint64(bytes8(_extractBytes(data, 152, 8)));
        address srcOwner = address(bytes20(_extractBytes(data, 172, 20)));
        uint64 destChainId = uint64(bytes8(_extractBytes(data, 216, 8)));
        address destOwner = address(bytes20(_extractBytes(data, 236, 20)));
        address to = address(bytes20(_extractBytes(data, 268, 20)));
        uint256 value = uint256(bytes32(_extractBytes(data, 288, 32)));

        uint256 dataOffset = uint256(bytes32(_extractBytes(data, 320, 32)));
        uint256 dataLength = uint256(bytes32(_extractBytes(data, dataOffset, 32)));
        bytes memory msgData = _extractBytes(data, dataOffset + 32, dataLength);

        return IBridge.Message({
            id: id,
            fee: fee,
            gasLimit: gasLimit,
            from: from,
            srcChainId: srcChainId,
            srcOwner: srcOwner,
            destChainId: destChainId,
            destOwner: destOwner,
            to: to,
            value: value,
            data: msgData
        });
    }

    /// @notice Slices bytes array
    function _slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    /// @notice Extracts bytes from a bytes array
    function _extractBytes(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        return _slice(data, start, length);
    }

    /// @notice Simulates the bridge delivering a message to the target contract
    function _simulateMessageDelivery(
        address l1Bridge,
        IBridge.Message memory message,
        bytes32 msgHash,
        bool verbose
    ) internal {
        IBridge.Context memory ctx =
            IBridge.Context({msgHash: msgHash, from: message.from, srcChainId: message.srcChainId});

        vm.mockCall(l1Bridge, abi.encodeWithSelector(IBridge.context.selector), abi.encode(ctx));

        vm.prank(l1Bridge);
        (bool success, bytes memory returnData) = message.to.call{value: message.value}(message.data);

        if (verbose) {
            emit MessageRelayed(msgHash, message.from, message.to, message.srcChainId, success);
            if (!success) {
                emit log_named_bytes("Revert reason", returnData);
            }
        }

        vm.clearMockedCalls();

        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    /// @notice Computes the hash of a message
    function _hashMessage(IBridge.Message memory message) internal pure returns (bytes32) {
        return keccak256(abi.encode(message));
    }

    /// @notice Tries to select a fork
    function _trySelectFork(uint256 forkId) internal returns (bool) {
        try vm.selectFork(forkId) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Extracts message hash from a MessageSent log
    function extractMsgHash(Vm.Log calldata log) external pure returns (bytes32 msgHash) {
        require(log.topics[0] == MESSAGE_SENT_SELECTOR, "Not a MessageSent event");
        return log.topics[1];
    }

    /// @notice Extracts and decodes a Message from a MessageSent log
    function extractMessage(Vm.Log calldata log) external pure returns (IBridge.Message memory message) {
        require(log.topics[0] == MESSAGE_SENT_SELECTOR, "Not a MessageSent event");
        return _decodeMessageFromLog(log.data);
    }

    /// @notice Filters logs to only include MessageSent events from a specific bridge
    function filterMessageSentLogs(
        Vm.Log[] calldata logs,
        address bridge
    ) external pure returns (Vm.Log[] memory filtered) {
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == bridge && logs[i].topics[0] == MESSAGE_SENT_SELECTOR) {
                count++;
            }
        }

        filtered = new Vm.Log[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == bridge && logs[i].topics[0] == MESSAGE_SENT_SELECTOR) {
                filtered[j] = logs[i];
                j++;
            }
        }
    }
}
