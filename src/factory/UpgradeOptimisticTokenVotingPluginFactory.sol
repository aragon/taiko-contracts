// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {OptimisticTokenVotingPlugin} from "../OptimisticTokenVotingPlugin.sol";
import {OptimisticTokenVotingPluginSetup} from "../setup/OptimisticTokenVotingPluginSetup.sol";

/// @title UpgradeOptimisticTokenVotingPluginFactory
/// @notice Encapsulates the full PSP-based upgrade flow for OptimisticTokenVotingPlugin
///         from Build 1 to Build 2, enabling end-to-end testing in Foundry.
/// @dev Prerequisites before calling `upgrade()`:
///      1. This contract must have ROOT_PERMISSION on the DAO.
///      2. This contract must have MAINTAINER_PERMISSION on the PluginRepo.
///      The factory revokes its own ROOT at the end, making it single-use.
///      The caller must revoke MAINTAINER_PERMISSION from this contract on the PluginRepo afterwards.
contract UpgradeOptimisticTokenVotingPluginFactory {
    struct UpgradeParams {
        DAO dao;
        PluginSetupProcessor psp;
        OptimisticTokenVotingPlugin plugin;
        PluginRepo pluginRepo;
        address votingToken;
        address l2VetoReceiver;
    }

    /// @notice The new PluginSetup deployed by this factory.
    OptimisticTokenVotingPluginSetup public immutable newSetup;

    constructor(GovernanceERC20 _governanceERC20Base, GovernanceWrappedERC20 _governanceWrappedERC20Base) {
        newSetup = new OptimisticTokenVotingPluginSetup(_governanceERC20Base, _governanceWrappedERC20Base);
    }

    /// @notice Executes the full plugin upgrade from Build 1 to Build 2.
    function upgrade(UpgradeParams calldata _params) external {
        // 1. Register Build 2 in the plugin repo
        _params.pluginRepo.createVersion(1, address(newSetup), bytes(""), bytes(""));

        // 2. Grant temporary permissions for PSP
        _grantPspPermissions(_params);

        // 3-4. Prepare and apply update
        _prepareAndApplyUpdate(_params);

        // 5. Configure L2 veto receiver
        _configureL2VetoReceiver(_params);

        // 6-7. Revoke temporary permissions + own ROOT
        _revokeAllPermissions(_params);
    }

    function _grantPspPermissions(UpgradeParams calldata _params) internal {
        _params.dao.grant(address(_params.dao), address(_params.psp), _params.dao.ROOT_PERMISSION_ID());
        _params.dao.grant(address(_params.psp), address(this), _params.psp.APPLY_UPDATE_PERMISSION_ID());
        _params.dao.grant(address(_params.plugin), address(_params.psp), _params.plugin.UPGRADE_PLUGIN_PERMISSION_ID());
    }

    function _prepareAndApplyUpdate(UpgradeParams calldata _params) internal {
        address[] memory currentHelpers = new address[](1);
        currentHelpers[0] = _params.votingToken;

        (bytes memory initData, IPluginSetup.PreparedSetupData memory preparedSetupData) = _params.psp.prepareUpdate(
            address(_params.dao),
            PluginSetupProcessor.PrepareUpdateParams({
                currentVersionTag: PluginRepo.Tag(1, 1),
                newVersionTag: PluginRepo.Tag(1, 2),
                pluginSetupRepo: _params.pluginRepo,
                setupPayload: IPluginSetup.SetupPayload({
                    plugin: address(_params.plugin),
                    currentHelpers: currentHelpers,
                    data: hex""
                })
            })
        );

        _params.psp.applyUpdate(
            address(_params.dao),
            PluginSetupProcessor.ApplyUpdateParams({
                plugin: address(_params.plugin),
                pluginSetupRef: PluginSetupRef(PluginRepo.Tag(1, 2), _params.pluginRepo),
                initData: initData,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            })
        );
    }

    function _configureL2VetoReceiver(UpgradeParams calldata _params) internal {
        bytes32 l2VetoPermission = _params.plugin.UPDATE_L2_VETO_RECEIVER_PERMISSION_ID();
        _params.dao.grant(address(_params.plugin), address(this), l2VetoPermission);
        _params.plugin.setL2VetoReceiver(_params.l2VetoReceiver);
        _params.dao.revoke(address(_params.plugin), address(this), l2VetoPermission);
    }

    function _revokeAllPermissions(UpgradeParams calldata _params) internal {
        _params.dao.revoke(
            address(_params.plugin), address(_params.psp), _params.plugin.UPGRADE_PLUGIN_PERMISSION_ID()
        );
        _params.dao.revoke(address(_params.psp), address(this), _params.psp.APPLY_UPDATE_PERMISSION_ID());
        _params.dao.revoke(address(_params.dao), address(_params.psp), _params.dao.ROOT_PERMISSION_ID());

        // Revoke own ROOT (single-use)
        _params.dao.revoke(address(_params.dao), address(this), _params.dao.ROOT_PERMISSION_ID());
    }
}
