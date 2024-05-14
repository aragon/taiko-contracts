// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

/// @title PublicKeyRegistry - Release 1, Build 1
/// @author Aragon Association - 2024
/// @notice A smart contract where any wallet can register its own libsodium public key for encryption purposes
contract PublicKeyRegistry {
    mapping(address => bytes32) internal publicKeys;

    /// @notice Emitted when a public key is registered
    event PublicKeyRegistered(address wallet, bytes32 publicKey);

    /// @notice Raised when the public key of the given user has already been set
    error AlreadySet();

    function setPublicKey(bytes32 _publicKey) public {
        if (publicKeys[msg.sender] != 0) revert AlreadySet();

        publicKeys[msg.sender] = _publicKey;
        emit PublicKeyRegistered(msg.sender, _publicKey);
    }

    function getPublicKey(address _wallet) public view returns (bytes32) {
        return publicKeys[_wallet];
    }
}
