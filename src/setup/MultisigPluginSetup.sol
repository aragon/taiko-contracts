// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetup, IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {Multisig} from "../Multisig.sol";

/// @title MultisigSetup - Release 1, Build 1
/// @author Aragon Association - 2022-2023
/// @notice The setup contract of the `Multisig` plugin.
contract MultisigPluginSetup is PluginSetup {
    /// @notice The address of `Multisig` plugin logic contract to be used in creating proxy contracts.
    Multisig private immutable multisigBase;

    /// @notice The contract constructor, that deploys the `Multisig` plugin logic contract.
    constructor() {
        multisigBase = new Multisig();
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(address _dao, bytes calldata _data)
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        // Decode `_data` to extract the parameters needed for deploying and initializing `Multisig` plugin.
        (address[] memory members, Multisig.MultisigSettings memory multisigSettings) =
            decodeInstallationParameters(_data);

        // Prepare and Deploy the plugin proxy.
        plugin = createERC1967Proxy(
            address(multisigBase), abi.encodeCall(Multisig.initialize, (IDAO(_dao), members, multisigSettings))
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](2);

        // Set permissions to be granted.
        // Grant the list of permissions of the plugin to the DAO.
        permissions[0] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            plugin,
            _dao,
            PermissionLib.NO_CONDITION,
            multisigBase.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        permissions[1] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            plugin,
            _dao,
            PermissionLib.NO_CONDITION,
            multisigBase.UPGRADE_PLUGIN_PERMISSION_ID()
        );

        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUpdate(address _dao, uint16 _currentBuild, SetupPayload calldata _payload)
        external
        pure
        override
        returns (bytes memory initData, PreparedSetupData memory preparedSetupData)
    {}

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(address _dao, SetupPayload calldata _payload)
        external
        view
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        // Prepare permissions
        permissions = new PermissionLib.MultiTargetPermission[](2);

        // Set permissions to be Revoked.
        permissions[0] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            _dao,
            PermissionLib.NO_CONDITION,
            multisigBase.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        permissions[1] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            _dao,
            PermissionLib.NO_CONDITION,
            multisigBase.UPGRADE_PLUGIN_PERMISSION_ID()
        );
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view returns (address) {
        return address(multisigBase);
    }

    /// @notice Encodes the given installation parameters into a byte array
    function encodeInstallationParameters(address[] memory _members, Multisig.MultisigSettings memory _multisigSettings)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(_members, _multisigSettings);
    }

    /// @notice Decodes the given byte array into the original installation parameters
    function decodeInstallationParameters(bytes memory _data)
        public
        pure
        returns (address[] memory _members, Multisig.MultisigSettings memory _multisigSettings)
    {
        (_members, _multisigSettings) = abi.decode(_data, (address[], Multisig.MultisigSettings));
    }
}
