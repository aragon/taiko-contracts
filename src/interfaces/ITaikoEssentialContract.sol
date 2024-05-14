// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IEssentialContract {
    /// @notice Pauses the contract.
    function pause() external;

    /// @notice Unpauses the contract.
    function unpause() external;

    function impl() external view returns (address);

    /// @notice Returns true if the contract is paused, and false otherwise.
    /// @return true if paused, false otherwise.
    function paused() external view returns (bool);

    function inNonReentrant() external view returns (bool);
}
