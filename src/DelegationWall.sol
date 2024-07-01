// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

/// @title DelegationWall - Release 1, Build 1
/// @author Aragon Association - 2024
/// @notice A smart contract where any wallet can register its own libsodium public key for encryption purposes
contract DelegationWall {
    struct Candidate {
        bytes message;
        bytes socialUrl;
    }

    /// @dev Stores the data registered by the delegate candidates
    mapping(address => Candidate) public candidates;
    /// @dev Keeps track of the addresses that have been already registered, used to enumerate.
    address[] public candidateAddresses;

    /// @notice Emitted when a wallet registers as a candidate
    event CandidateRegistered(address indexed candidate, bytes message, bytes socialUrl);

    /// @notice Raised when a delegate registers with an empty message
    error EmptyMessage();

    function register(bytes memory _message, bytes memory _socialUrl) public {
        if (_message.length == 0) revert EmptyMessage();

        if (candidates[msg.sender].message.length == 0) {
            candidateAddresses.push(msg.sender);
        }

        candidates[msg.sender].message = _message;
        candidates[msg.sender].socialUrl = _socialUrl;

        emit CandidateRegistered(msg.sender, _message, _socialUrl);
    }

    function candidateCount() public view returns (uint256) {
        return candidateAddresses.length;
    }
}
