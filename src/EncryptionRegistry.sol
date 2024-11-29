// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IEncryptionRegistry} from "./interfaces/IEncryptionRegistry.sol";

/// @title EncryptionRegistry - Release 1, Build 1
/// @author Aragon Association - 2024
/// @notice A smart contract where accounts can register their libsodium public key for encryption purposes, as well as appointing an EOA
contract EncryptionRegistry is IEncryptionRegistry, ERC165 {
    struct AccountEntry {
        address appointedWallet;
        bytes32 publicKey;
    }

    /// @notice Allows to enumerate the addresses on the registry
    address[] public registeredAccounts;

    /// @notice The database of appointed wallets and their public key
    mapping(address => AccountEntry) public accounts;

    /// @notice A reference to the account that appointed each wallet
    mapping(address => address) public appointerOf;

    /// @dev The contract to check whether the caller is a multisig member
    Addresslist addresslist;

    constructor(Addresslist _addresslist) {
        if (!IERC165(address(_addresslist)).supportsInterface(type(Addresslist).interfaceId)) {
            revert InvalidAddressList();
        }

        addresslist = _addresslist;
    }

    /// @inheritdoc IEncryptionRegistry
    function appointWallet(address _newWallet) public {
        // Appointing ourselves is the same as unappointing
        if (_newWallet == msg.sender) _newWallet = address(0);

        if (!addresslist.isListed(msg.sender)) {
            revert MustBeListed();
        } else if (Address.isContract(_newWallet)) {
            revert CannotAppointContracts();
        } else if (addresslist.isListed(_newWallet)) {
            // Appointing an already listed signer is not allowed, as votes would be locked
            revert AlreadyListed();
        } else if (_newWallet == accounts[msg.sender].appointedWallet) {
            return; // done
        } else if (appointerOf[_newWallet] != address(0)) {
            revert AlreadyAppointed();
        }

        bool exists;
        for (uint256 i = 0; i < registeredAccounts.length;) {
            if (registeredAccounts[i] == msg.sender) {
                exists = true;
                break;
            }
            unchecked {
                i++;
            }
        }

        // New account?
        if (!exists) {
            registeredAccounts.push(msg.sender);
        }
        // Existing account
        else {
            // Clear the current appointerOf[], if needed
            if (accounts[msg.sender].appointedWallet != address(0)) {
                appointerOf[accounts[msg.sender].appointedWallet] = address(0);
            }
            // Clear the current public key, if needed
            if (accounts[msg.sender].publicKey != bytes32(0)) {
                // The old appointed wallet should no longer be able to see new content
                accounts[msg.sender].publicKey = bytes32(0);
            }
        }

        accounts[msg.sender].appointedWallet = _newWallet;
        if (_newWallet != address(0)) {
            appointerOf[_newWallet] = msg.sender;
        }
        emit WalletAppointed(msg.sender, _newWallet);
    }

    /// @inheritdoc IEncryptionRegistry
    function setOwnPublicKey(bytes32 _publicKey) public {
        if (!addresslist.isListed(msg.sender)) {
            revert MustBeListed();
        }
        // If someone else if appointed, the public key cannot be overriden.
        // The appointed value should be set to address(0) or msg.sender first.
        else if (
            accounts[msg.sender].appointedWallet != address(0) && accounts[msg.sender].appointedWallet != msg.sender
        ) {
            revert MustResetAppointment();
        }

        _setPublicKey(msg.sender, _publicKey);
        emit PublicKeySet(msg.sender, _publicKey);
    }

    /// @inheritdoc IEncryptionRegistry
    function setPublicKey(address _accountOwner, bytes32 _publicKey) public {
        if (!addresslist.isListed(_accountOwner)) {
            revert MustBeListed();
        } else if (accounts[_accountOwner].appointedWallet != msg.sender) {
            revert MustBeAppointed();
        }

        _setPublicKey(_accountOwner, _publicKey);
        emit PublicKeySet(_accountOwner, _publicKey);
    }

    /// @inheritdoc IEncryptionRegistry
    function getRegisteredAccounts() public view returns (address[] memory) {
        return registeredAccounts;
    }

    /// @inheritdoc IEncryptionRegistry
    function getAppointedWallet(address _member) public view returns (address) {
        if (accounts[_member].appointedWallet != address(0)) {
            return accounts[_member].appointedWallet;
        }
        return _member;
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IEncryptionRegistry).interfaceId || super.supportsInterface(_interfaceId);
    }

    // Internal helpers

    function _setPublicKey(address _account, bytes32 _publicKey) internal {
        bool exists;
        for (uint256 i = 0; i < registeredAccounts.length;) {
            if (registeredAccounts[i] == _account) {
                exists = true;
                break;
            }
            unchecked {
                i++;
            }
        }
        if (!exists) {
            // New account
            registeredAccounts.push(_account);
        }

        accounts[_account].publicKey = _publicKey;
    }
}
