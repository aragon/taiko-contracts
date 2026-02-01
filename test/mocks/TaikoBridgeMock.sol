// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBridge} from "../../src/interfaces/IBridge.sol";

/// @title TaikoBridgeMock
/// @notice Mock bridge for unit testing without forks
contract TaikoBridgeMock is IBridge {
    Context private _context;
    mapping(bytes32 => Status) private _statuses;
    mapping(bytes32 => bool) private _sent;

    uint64 private _nextMessageId;
    Message[] public sentMessages;

    /// @notice Sets the context for the next message invocation
    function setContext(Context memory ctx) external {
        _context = ctx;
    }

    /// @notice Sets the status of a message
    function setMessageStatus(bytes32 msgHash, Status status) external {
        _statuses[msgHash] = status;
    }

    function sendMessage(
        Message calldata _message
    ) external payable override returns (bytes32 msgHash_, Message memory message_) {
        message_ = Message({
            id: _nextMessageId++,
            fee: _message.fee,
            gasLimit: _message.gasLimit,
            from: msg.sender,
            srcChainId: uint64(block.chainid),
            srcOwner: _message.srcOwner,
            destChainId: _message.destChainId,
            destOwner: _message.destOwner,
            to: _message.to,
            value: _message.value,
            data: _message.data
        });

        msgHash_ = hashMessage(message_);
        _sent[msgHash_] = true;
        sentMessages.push(message_);

        emit MessageSent(msgHash_, message_);
    }

    function recallMessage(Message calldata, bytes calldata) external pure override {
        revert("TaikoBridgeMock: recallMessage not implemented");
    }

    function context() external view override returns (Context memory ctx_) {
        return _context;
    }

    function isMessageSent(Message calldata _message) external view override returns (bool) {
        return _sent[hashMessage(_message)];
    }

    function processMessage(
        Message calldata _message,
        bytes calldata
    ) external override returns (Status status_, StatusReason reason_) {
        bytes32 msgHash = hashMessage(_message);
        _statuses[msgHash] = Status.DONE;

        // Set context before calling target
        _context = Context({msgHash: msgHash, from: _message.from, srcChainId: _message.srcChainId});

        // Call the target
        (bool success,) = _message.to.call{value: _message.value}(_message.data);

        // Clear context
        delete _context;

        if (success) {
            return (Status.DONE, StatusReason.INVOCATION_OK);
        } else {
            return (Status.FAILED, StatusReason.INVOCATION_FAILED);
        }
    }

    function retryMessage(Message calldata, bool) external pure override {
        revert("TaikoBridgeMock: retryMessage not implemented");
    }

    function failMessage(Message calldata) external pure override {
        revert("TaikoBridgeMock: failMessage not implemented");
    }

    function hashMessage(Message memory _message) public pure override returns (bytes32) {
        return keccak256(abi.encode(_message));
    }

    function nextMessageId() external view override returns (uint64) {
        return _nextMessageId;
    }

    /// @notice Helper to get all sent messages
    function getSentMessages() external view returns (Message[] memory) {
        return sentMessages;
    }

    /// @notice Helper to clear state between tests
    function reset() external {
        _nextMessageId = 0;
        delete sentMessages;
    }
}
