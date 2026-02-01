// SPDX-License-Identifier: MIT
// Source: https://github.com/taikoxyz/taiko-mono/blob/main/packages/protocol/contracts/shared/bridge/IBridge.sol
pragma solidity ^0.8.17;

/// @title IMessageInvocable
/// @notice An interface that all bridge message receiver shall implement.
interface IMessageInvocable {
    /// @notice Called when this contract is the bridge target.
    /// @param _data The data for this contract to interpret.
    /// @dev This method should be guarded with `onlyFromNamed("bridge")`.
    function onMessageInvocation(bytes calldata _data) external payable;
}
