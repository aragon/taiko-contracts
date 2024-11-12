// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {ISignerList} from "./interfaces/ISignerList.sol";
import {EncryptionRegistry} from "./EncryptionRegistry.sol";
import {DaoAuthorizableUpgradeable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IEncryptionRegistry} from "./interfaces/IEncryptionRegistry.sol";

// ID of the permission required to call the `addAddresses` and `removeAddresses` functions.
bytes32 constant UPDATE_SIGNER_LIST_PERMISSION_ID = keccak256("UPDATE_SIGNER_LIST_PERMISSION");

// ID of the permission required to update the SignerList settings.
bytes32 constant UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID = keccak256("UPDATE_SIGNER_LIST_SETTINGS_PERMISSION");

/// @title SignerList - Release 1, Build 1
/// @author Aragon Association - 2024
/// @notice A smart contract acting as the source of truth for multisig censuses, as well as defining who is appointed as an EOA for decryption purposes.
contract SignerList is ISignerList, Addresslist, ERC165Upgradeable, DaoAuthorizableUpgradeable {
    /// @notice Thrown if the signer list length is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error SignerListLengthOutOfBounds(uint16 limit, uint256 actual);

    /// @notice Thrown when attempting to define an invalid EncryptionRegistry
    error InvalidEncryptionRegitry(address givenAddress);

    /// @notice Emitted when the SignerList settings are updated
    event SignerListSettingsUpdated(EncryptionRegistry encryptionRegistry, uint16 minSignerListLength);

    struct Settings {
        /// @notice The contract where current signers can appoint wallets for decryption purposes
        EncryptionRegistry encryptionRegistry;
        /// @notice The minimum amount of addresses required.
        /// @notice Set this value to at least the `minApprovals` of the EmergencyMultisig contract.
        uint16 minSignerListLength;
    }

    Settings public settings;

    /// @notice Disables the initializers on the implementation contract to prevent it from being left uninitialized.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes Release 1, Build 1 without any settings yet.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @dev updateSettings() must be called after the EncryptionRegistry has been deployed.
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _signers The addresses of the initial signers to be added.
    function initialize(IDAO _dao, address[] calldata _signers) external initializer {
        __DaoAuthorizableUpgradeable_init(_dao);

        // Validating _signers[]
        if (_signers.length > type(uint16).max) {
            revert SignerListLengthOutOfBounds({limit: type(uint16).max, actual: _signers.length});
        }

        _addAddresses(_signers);
        emit SignersAdded({signers: _signers});
    }

    /// @inheritdoc ISignerList
    function addSigners(address[] calldata _signers) external auth(UPDATE_SIGNER_LIST_PERMISSION_ID) {
        uint256 newAddresslistLength = addresslistLength() + _signers.length;

        // Check if the new address list length would be greater than `type(uint16).max`, the maximal number of approvals.
        if (newAddresslistLength > type(uint16).max) {
            revert SignerListLengthOutOfBounds({limit: type(uint16).max, actual: newAddresslistLength});
        }

        _addAddresses(_signers);
        emit SignersAdded({signers: _signers});
    }

    /// @inheritdoc ISignerList
    function removeSigners(address[] calldata _signers) external auth(UPDATE_SIGNER_LIST_PERMISSION_ID) {
        uint16 newAddresslistLength = uint16(addresslistLength() - _signers.length);

        // Check if the new address list length would become less than the current minimum number of approvals required.
        if (newAddresslistLength < settings.minSignerListLength) {
            revert SignerListLengthOutOfBounds({limit: settings.minSignerListLength, actual: newAddresslistLength});
        }

        _removeAddresses(_signers);
        emit SignersRemoved({signers: _signers});
    }

    /// @notice Updates the plugin settings.
    /// @param _newSettings The new settings.
    function updateSettings(Settings calldata _newSettings) external auth(UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID) {
        // Values validated within _updateSettings
        _updateSettings(_newSettings);

        emit SignerListSettingsUpdated({
            encryptionRegistry: _newSettings.encryptionRegistry,
            minSignerListLength: _newSettings.minSignerListLength
        });
    }

    /// @inheritdoc ISignerList
    function isListedOrAppointedByListed(address _address) public view returns (bool listedOrAppointedByListed) {
        if (isListed(_address)) {
            return true;
        } else if (isListed(settings.encryptionRegistry.appointedBy(_address))) {
            return true;
        }

        // Not found, return blank (false)
    }

    /// @inheritdoc ISignerList
    function getListedOwnerAtBlock(address _address, uint256 _blockNumber) public view returns (address _owner) {
        if (isListedAtBlock(_address, _blockNumber)) {
            return _address;
        }
        address _appointer = settings.encryptionRegistry.appointedBy(_address);
        if (isListedAtBlock(_appointer, _blockNumber)) {
            return _appointer;
        }

        // Not found, return a blank address
    }

    /// @inheritdoc ISignerList
    function resolveAccountAtBlock(address _address, uint256 _blockNumber)
        public
        view
        returns (address _owner, address _voter)
    {
        if (isListedAtBlock(_address, _blockNumber)) {
            // The owner + the voter
            return (_address, settings.encryptionRegistry.getAppointedWallet(_address));
        }

        address _appointer = settings.encryptionRegistry.appointedBy(_address);
        if (this.isListedAtBlock(_appointer, _blockNumber)) {
            // The appointed wallet votes
            return (_appointer, _address);
        }

        // Not found, returning empty addresses
    }

    /// @inheritdoc ISignerList
    function getEncryptionRecipients() external view returns (address[] memory result) {
        address[] memory _encryptionAccounts = settings.encryptionRegistry.getRegisteredAccounts();

        // Allocating the full length.
        // If any member is no longer listed, the size will be decreased.
        result = new address[](_encryptionAccounts.length);

        uint256 rIdx; // Result iterator. Will never be greater than erIdx.
        uint256 erIdx; // EncryptionRegistry iterator
        address appointed;
        for (erIdx = 0; erIdx < _encryptionAccounts.length;) {
            if (isListed(_encryptionAccounts[erIdx])) {
                // Add it to the result array if listed
                appointed = settings.encryptionRegistry.getAppointedWallet(_encryptionAccounts[erIdx]);
                // Use the appointed address if non-zero
                if (appointed != address(0)) {
                    result[rIdx] = appointed;
                } else {
                    result[rIdx] = _encryptionAccounts[erIdx];
                }

                unchecked {
                    rIdx++;
                }
            }
            // Skip non-listed accounts othersise

            unchecked {
                erIdx++;
            }
        }

        if (rIdx < erIdx) {
            // Decrease the array size to return listed accounts without blank entries
            uint256 diff = erIdx - rIdx;
            assembly {
                mstore(result, sub(mload(result), diff))
            }
        }
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(ISignerList).interfaceId || _interfaceId == type(Addresslist).interfaceId
            || super.supportsInterface(_interfaceId);
    }

    // Internal helpers

    /// @notice Internal function to update the plugin settings.
    /// @param _newSettings The new settings.
    function _updateSettings(Settings calldata _newSettings) internal {
        // Avoid writing if not needed
        if (
            _newSettings.encryptionRegistry == settings.encryptionRegistry
                && _newSettings.minSignerListLength == settings.minSignerListLength
        ) {
            return;
        } else if (!_newSettings.encryptionRegistry.supportsInterface(type(IEncryptionRegistry).interfaceId)) {
            revert InvalidEncryptionRegitry(address(_newSettings.encryptionRegistry));
        }

        uint16 _currentLength = uint16(addresslistLength());
        if (_newSettings.minSignerListLength > _currentLength) {
            revert SignerListLengthOutOfBounds({limit: _currentLength, actual: _newSettings.minSignerListLength});
        }

        settings = _newSettings;
    }
}
