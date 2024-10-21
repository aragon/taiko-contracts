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

    /// @notice Initializes Release 1, Build 1.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _signers The addresses of the initial signers to be added.
    /// @param _settings The settings to define on the new instance.
    function initialize(IDAO _dao, address[] calldata _signers, Settings calldata _settings) external initializer {
        __DaoAuthorizableUpgradeable_init(_dao);

        // Validating _signers[]
        if (_signers.length > type(uint16).max) {
            revert SignerListLengthOutOfBounds({limit: type(uint16).max, actual: _signers.length});
        }

        _addAddresses(_signers);
        emit SignersAdded({signers: _signers});

        // Settings (validated within _updateSettings)
        _updateSettings(_settings);
        emit SignerListSettingsUpdated({
            encryptionRegistry: _settings.encryptionRegistry,
            minSignerListLength: _settings.minSignerListLength
        });
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
    function resolveEncryptionAccountStatus(address _sender)
        public
        view
        returns (bool ownerIsListed, bool isAppointed)
    {
        if (this.isListed(_sender)) {
            ownerIsListed = true;
        } else if (this.isListed(settings.encryptionRegistry.appointedBy(_sender))) {
            ownerIsListed = true;
            isAppointed = true;
        }

        // Not found, return blank values
    }

    /// @inheritdoc ISignerList
    function resolveEncryptionOwner(address _sender) public view returns (address owner) {
        (bool ownerIsListed, bool isAppointed) = resolveEncryptionAccountStatus(_sender);

        if (!ownerIsListed) return address(0);
        else if (isAppointed) return settings.encryptionRegistry.appointedBy(_sender);
        return _sender;
    }

    /// @inheritdoc ISignerList
    function resolveEncryptionAccount(address _sender) public view returns (address owner, address appointedWallet) {
        (bool ownerIsListed, bool isAppointed) = resolveEncryptionAccountStatus(_sender);

        if (ownerIsListed) {
            if (isAppointed) {
                owner = settings.encryptionRegistry.appointedBy(_sender);
                appointedWallet = _sender;
            } else {
                owner = _sender;
                appointedWallet = settings.encryptionRegistry.getAppointedWallet(_sender);
            }
        }

        // Not found, return blank values
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
        } else if (
            !IERC165(address(_newSettings.encryptionRegistry)).supportsInterface(type(IEncryptionRegistry).interfaceId)
        ) {
            revert InvalidEncryptionRegitry(address(_newSettings.encryptionRegistry));
        }

        uint16 _currentLength = uint16(addresslistLength());
        if (_newSettings.minSignerListLength > _currentLength) {
            revert SignerListLengthOutOfBounds({limit: _currentLength, actual: _newSettings.minSignerListLength});
        }

        settings = _newSettings;
    }
}
