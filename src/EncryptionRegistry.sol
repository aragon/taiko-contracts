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
    struct RegisteredAccount {
        address appointedAgent;
        bytes32 publicKey;
    }

    /// @notice Allows to enumerate the addresses on the registry
    address[] public accountList;

    /// @notice The public key and (optional) appointed agent or each registered account
    mapping(address => RegisteredAccount) public accounts;

    /// @notice A reference to the account that appointed each agent
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
    function appointAgent(address _newAgent) public {
        // Appointing ourselves is the same as unappointing
        if (_newAgent == msg.sender) _newAgent = address(0);

        if (!addresslist.isListed(msg.sender)) {
            revert MustBeListed();
        } else if (Address.isContract(_newAgent)) {
            revert CannotAppointContracts();
        } else if (addresslist.isListed(_newAgent)) {
            // Appointing an already listed signer is not allowed, as votes would be locked
            revert AlreadyListed();
        } else if (_newAgent == accounts[msg.sender].appointedAgent) {
            return; // done
        } else if (appointerOf[_newAgent] != address(0)) {
            revert AlreadyAppointed();
        }

        bool exists;
        for (uint256 i = 0; i < accountList.length;) {
            if (accountList[i] == msg.sender) {
                exists = true;
                break;
            }
            unchecked {
                i++;
            }
        }

        // New account?
        if (!exists) {
            accountList.push(msg.sender);
        }
        // Existing account
        else {
            // Clear the current appointerOf[], if needed
            if (accounts[msg.sender].appointedAgent != address(0)) {
                appointerOf[accounts[msg.sender].appointedAgent] = address(0);
            }
            // Clear the current public key, if needed
            if (accounts[msg.sender].publicKey != bytes32(0)) {
                // The old appointed agent should no longer be able to see new content
                accounts[msg.sender].publicKey = bytes32(0);
            }
        }

        accounts[msg.sender].appointedAgent = _newAgent;
        if (_newAgent != address(0)) {
            appointerOf[_newAgent] = msg.sender;
        }
        emit AgentAppointed(msg.sender, _newAgent);
    }

    /// @inheritdoc IEncryptionRegistry
    function setOwnPublicKey(bytes32 _publicKey) public {
        if (!addresslist.isListed(msg.sender)) {
            revert MustBeListed();
        }
        // If someone else if appointed, the public key cannot be overriden.
        // The appointed value should be set to address(0) or msg.sender first.
        else if (accounts[msg.sender].appointedAgent != address(0) && accounts[msg.sender].appointedAgent != msg.sender)
        {
            revert MustResetAppointedAgent();
        }

        _setPublicKey(msg.sender, _publicKey);
        emit PublicKeySet(msg.sender, _publicKey);
    }

    /// @inheritdoc IEncryptionRegistry
    function setPublicKey(address _accountOwner, bytes32 _publicKey) public {
        if (!addresslist.isListed(_accountOwner)) {
            revert MustBeListed();
        } else if (accounts[_accountOwner].appointedAgent != msg.sender) {
            revert MustBeAppointed();
        }

        _setPublicKey(_accountOwner, _publicKey);
        emit PublicKeySet(_accountOwner, _publicKey);
    }

    /// @inheritdoc IEncryptionRegistry
    function getRegisteredAccounts() public view returns (address[] memory) {
        return accountList;
    }

    /// @inheritdoc IEncryptionRegistry
    function getAppointedAgent(address _account) public view returns (address) {
        if (accounts[_account].appointedAgent != address(0)) {
            return accounts[_account].appointedAgent;
        }
        return _account;
    }
    
    /// @notice Removes the addresses on accountList which are not a signer on the SignerList
    function removeUnused() public {
        for (uint256 i = 0; i < accountList.length; ) {
            if (!addresslist.isListed(accountList[i])) {
                // Swap it with the last element and remove it
                accountList[i] = accountList[accountList.length - 1];
                accountList.pop();
                continue;
            }
            unchecked {
                i++;
            }
        }
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
        for (uint256 i = 0; i < accountList.length;) {
            if (accountList[i] == _account) {
                exists = true;
                break;
            }
            unchecked {
                i++;
            }
        }
        if (!exists) {
            // New account
            accountList.push(_account);
        }

        accounts[_account].publicKey = _publicKey;
    }
}
