// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

/// @title PublicKeyRegistry - Release 1, Build 1
/// @author Aragon Association - 2024
/// @notice A smart contract where any wallet can register its own libsodium public key for encryption purposes
contract PublicKeyRegistry {
    mapping(address => bytes32) public publicKeys;

    /// @dev Allows to enumerate the wallets that have a public key registered
    address[] public registeredWallets;

    /// @notice Emitted when a public key is registered
    event PublicKeyRegistered(address wallet, bytes32 publicKey);

    /// @notice Raised when the public key of the given user has already been set
    error AlreadySet();

    function setPublicKey(bytes32 _publicKey) public {
        if (publicKeys[msg.sender] != 0) revert AlreadySet();

        publicKeys[msg.sender] = _publicKey;
        emit PublicKeyRegistered(msg.sender, _publicKey);
        registeredWallets.push(msg.sender);
    }

    /// @notice Returns the list of wallets that have registered a public key
    /// @dev Use this function to get all addresses in a single call. You can still call registeredWallets[idx] to resolve them one by one.
    function getRegisteredWallets() public view returns (address[] memory) {
        return registeredWallets;
    }

    /// @notice Returns the number of publicKey entries available
    function registeredWalletCount() public view returns (uint256) {
        return registeredWallets.length;
    }
}
