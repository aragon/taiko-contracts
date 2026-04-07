// SPDX-License-Identifier: MIT
// Source: https://github.com/taikoxyz/taiko-mono/blob/df9a386a0b1e/packages/protocol/contracts/shared/bridge/IBridge.sol
// Pragma lowered from ^0.8.24 to ^0.8.17 for compatibility with Aragon OSx (=0.8.17)
pragma solidity ^0.8.17;

/// @title IBridge
/// @notice The bridge used in conjunction with the {ISignalService}.
/// @dev Ether is held by Bridges on L1 and L2s.
/// @custom:security-contact security@taiko.xyz
interface IBridge {
    enum Status {
        NEW,
        RETRIABLE,
        DONE,
        FAILED,
        RECALLED
    }

    enum StatusReason {
        INVOCATION_OK,
        INVOCATION_PROHIBITED,
        INVOCATION_FAILED,
        OUT_OF_ETH_QUOTA
    }

    struct Message {
        // Message ID whose value is automatically assigned.
        uint64 id;
        // The max processing fee for the relayer. This fee has 3 parts:
        // - the fee for message calldata.
        // - the minimal fee reserve for general processing, excluding function call.
        // - the invocation fee for the function call.
        // Any unpaid fee will be refunded to the destOwner on the destination chain.
        // Note that fee must be 0 if gasLimit is 0, or large enough to make the invocation fee
        // non-zero.
        uint64 fee;
        // gasLimit that the processMessage call must have.
        uint32 gasLimit;
        // The address, EOA or contract, that interacts with this bridge.
        // The value is automatically assigned.
        address from;
        // Source chain ID whose value is automatically assigned.
        uint64 srcChainId;
        // The owner of the message on the source chain.
        address srcOwner;
        // Destination chain ID where the `to` address lives.
        uint64 destChainId;
        // The owner of the message on the destination chain.
        address destOwner;
        // The destination address on the destination chain.
        address to;
        // value to invoke on the destination chain.
        uint256 value;
        // callData to invoke on the destination chain.
        bytes data;
    }

    // Struct representing the context of a bridge operation.
    // 2 slots
    struct Context {
        bytes32 msgHash; // Message hash.
        address from; // Sender's address.
        uint64 srcChainId; // Source chain ID.
    }

    /// @notice Emitted when a message is sent.
    /// @param msgHash The hash of the message.
    /// @param message The message.
    event MessageSent(bytes32 indexed msgHash, Message message);

    /// @notice Emitted when the status of a message changes.
    /// @param msgHash The hash of the message.
    /// @param status The new status of the message.
    event MessageStatusChanged(bytes32 indexed msgHash, Status status);

    /// @notice Sends a message to the destination chain and takes custody
    /// of Ether required in this contract.
    /// @param _message The message to be sent.
    /// @return msgHash_ The hash of the sent message.
    /// @return message_ The updated message sent.
    function sendMessage(
        Message calldata _message
    ) external payable returns (bytes32 msgHash_, Message memory message_);

    /// @notice Recalls a message on its source chain after it has failed on the
    /// destination chain, releasing associated assets on the source chain.
    /// @param _message The message whose associated Ether should be released.
    /// @param _proof The merkle inclusion proof.
    function recallMessage(Message calldata _message, bytes calldata _proof) external;

    /// @notice Processes a bridge message on the destination chain.
    /// @param _message The message to be processed.
    /// @param _proof The merkle inclusion proof.
    /// @return The message's status after processing and the reason for the change.
    function processMessage(
        Message calldata _message,
        bytes calldata _proof
    ) external returns (Status, StatusReason);

    /// @notice Retries to invoke the messageCall after releasing associated Ether and tokens.
    /// @param _message The message to retry.
    /// @param _isLastAttempt Specifies if this is the last attempt to retry the message.
    function retryMessage(Message calldata _message, bool _isLastAttempt) external;

    /// @notice Mark a message as failed if the message is currently retriable.
    /// @param _message The message to fail.
    function failMessage(Message calldata _message) external;

    /// @notice Returns the bridge state context.
    /// @return ctx_ The context of the current bridge operation.
    function context() external view returns (Context memory ctx_);

    /// @notice Checks if the message was sent.
    /// @param _message The message.
    /// @return true if the message was sent.
    function isMessageSent(Message calldata _message) external view returns (bool);

    /// @notice Returns the unique id of the next bridge message.
    /// @return A unique id.
    function nextMessageId() external view returns (uint64);

    /// @notice Hash the message.
    /// @param _message The message struct variable to be hashed.
    /// @return The message's hash.
    function hashMessage(Message memory _message) external pure returns (bytes32);
}
