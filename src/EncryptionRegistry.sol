// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title EncryptionRegistry - Release 1, Build 1
/// @author Aragon Association - 2024
/// @notice A smart contract where addresses can register their libsodium public key for encryption purposes, as well as appointing an EOA
contract EncryptionRegistry {
    struct RegistryEntry {
        address appointedWallet;
        bytes32 publicKey;
    }

    /// @dev Allows to enumerate the addresses that have a public key registered
    address[] public registeredAddresses;

    mapping(address => RegistryEntry) public members;

    /// @dev The contract to check whether the caller is a multisig member
    Addresslist addresslistSource;

    /// @notice Emitted when a public key is defined
    event PublicKeySet(address member, bytes32 publicKey);

    /// @notice Emitted when an externally owned wallet is appointed
    event WalletAppointed(address member, address appointedWallet);

    /// @notice Raised when attempting to register a contract instead of a wallet
    error CannotAppointContracts();

    /// @notice Raised when a non appointed wallet tried to define the public key
    error NotAppointed();

    /// @notice Raised when the member attempts to define the public key of the appointed wallet
    error OwnerNotAppointed();

    /// @notice Raised when the caller is not a multisig member
    error RegistrationForbidden();

    /// @notice Raised when the caller is not a multisig member
    error InvalidAddressList();

    constructor(Addresslist _addresslistSource) {
        if (!IERC165(address(_addresslistSource)).supportsInterface(type(Addresslist).interfaceId)) {
            revert InvalidAddressList();
        }

        addresslistSource = _addresslistSource;
    }

    /// @notice Registers the externally owned wallet's address to use for encryption. This allows smart contracts to appoint an EOA that can decrypt data.
    function appointWallet(address _newAddress) public {
        if (!addresslistSource.isListed(msg.sender)) revert RegistrationForbidden();
        else if (Address.isContract(_newAddress)) revert CannotAppointContracts();

        if (members[msg.sender].appointedWallet == address(0) && members[msg.sender].publicKey == bytes32(0)) {
            registeredAddresses.push(msg.sender);
        }

        if (members[msg.sender].publicKey != bytes32(0)) {
            // The old member should no longer be able to see new content
            members[msg.sender].publicKey = bytes32(0);
        }
        members[msg.sender].appointedWallet = _newAddress;
        emit WalletAppointed(msg.sender, _newAddress);
    }

    /// @notice Registers the given public key as its own target for decrypting messages
    function setOwnPublicKey(bytes32 _publicKey) public {
        if (!addresslistSource.isListed(msg.sender)) {
            revert RegistrationForbidden();
        } else if (
            members[msg.sender].appointedWallet != msg.sender && members[msg.sender].appointedWallet != address(0)
        ) {
            revert OwnerNotAppointed();
        }

        _setPublicKey(msg.sender, _publicKey);
    }

    /// @notice Registers the given public key as the member's target for decrypting messages. Only if the sender is appointed.
    function setPublicKey(address _memberAddress, bytes32 _publicKey) public {
        if (!addresslistSource.isListed(_memberAddress)) revert RegistrationForbidden();
        else if (members[_memberAddress].appointedWallet != msg.sender) revert NotAppointed();

        _setPublicKey(_memberAddress, _publicKey);
    }

    function _setPublicKey(address _memberAddress, bytes32 _publicKey) internal {
        if (members[_memberAddress].appointedWallet == address(0) && members[_memberAddress].publicKey == bytes32(0)) {
            registeredAddresses.push(_memberAddress);
        }

        members[_memberAddress].publicKey = _publicKey;
        emit PublicKeySet(_memberAddress, _publicKey);
    }

    /// @notice Returns the list of addresses on the registry
    /// @dev Use this function to get all addresses in a single call. You can still call registeredAddresses[idx] to resolve them one by one.
    function getRegisteredAddresses() public view returns (address[] memory) {
        return registeredAddresses;
    }

    /// @notice Returns the number of addresses registered
    function getRegisteredAddressesLength() public view returns (uint256) {
        return registeredAddresses.length;
    }
}
