// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Manual copy of lib/taiko-mono/packages/protocol/contracts/L1/TaikoL1.sol and its dependent structs
/// from https://github.com/taikoxyz/taiko-mono/tree/protocol-v1.9.0.
/// This is in order to overcome the conflicting compiler versions between 0.8.17 (OSx) and 0.8.24 (Taiko)
interface ITaikoL1 {
    /// @notice Returns true if the contract is paused, and false otherwise.
    /// @return true if paused, false otherwise.
    function paused() external view returns (bool);

    /// @notice Returns information about the last verified block.
    /// @return blockId The last verified block's ID.
    /// @return blockHash The last verified block's blockHash.
    /// @return stateRoot The last verified block's stateRoot.
    /// @return verifiedAt The timestamp this block is verified at.
    function getLastVerifiedBlock()
        external
        view
        returns (uint64 blockId, bytes32 blockHash, bytes32 stateRoot, uint64 verifiedAt);
}
