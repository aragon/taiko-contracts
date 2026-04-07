// SPDX-License-Identifier: MIT
// Source: https://github.com/taikoxyz/taiko-mono/blob/df9a386a0b1e/packages/protocol/contracts/shared/bridge/IBridge.sol
// Pragma lowered from ^0.8.24 to ^0.8.17 for compatibility with Aragon OSx (=0.8.17)
pragma solidity ^0.8.17;

/// @title IMessageInvocable
/// @notice An interface that all bridge message receiver shall implement.
interface IMessageInvocable {
    /// @notice Called when this contract is the bridge target.
    /// @param _data The data for this contract to interpret.
    /// @dev This method should be guarded with `onlyFromNamed("bridge")`.
    function onMessageInvocation(bytes calldata _data) external payable;
}
