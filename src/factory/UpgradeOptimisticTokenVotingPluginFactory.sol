// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
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
/// @dev All upgrade params are fixed at construction time to prevent parameter manipulation.
///      Usage:
///      1. Deploy this factory with all params.
///      2. Create a DAO proposal that:
///         a. Grants ROOT + MAINTAINER to this factory
///         b. Calls `upgrade()`
///         c. Revokes MAINTAINER from this factory
///         d. Calls `plugin.setL2VetoReceiver(receiver)` (DAO gets this permission from applyUpdate)
///         e. Calls `vetoReceiver.setTrustedL2Aggregator(aggregator)` (DAO gets this permission from applyUpdate)
///      The factory revokes its own ROOT at the end of `upgrade()`.
contract UpgradeOptimisticTokenVotingPluginFactory {
    /// @notice The new PluginSetup deployed by this factory.
    OptimisticTokenVotingPluginSetup public immutable newSetup;

    DAO public immutable dao;
    PluginSetupProcessor public immutable psp;
    OptimisticTokenVotingPlugin public immutable plugin;
    PluginRepo public immutable pluginRepo;
    address public immutable votingToken;
    address public immutable l2VetoReceiver;

    /// @notice Thrown when upgrade() has already been called.
    error AlreadyUpgraded();

    /// @notice Whether upgrade() has been called.
    bool public upgraded;

    constructor(
        GovernanceERC20 _governanceERC20Base,
        GovernanceWrappedERC20 _governanceWrappedERC20Base,
        DAO _dao,
        PluginSetupProcessor _psp,
        OptimisticTokenVotingPlugin _plugin,
        PluginRepo _pluginRepo,
        address _votingToken,
        address _l2VetoReceiver
    ) {
        newSetup = new OptimisticTokenVotingPluginSetup(_governanceERC20Base, _governanceWrappedERC20Base);
        dao = _dao;
        psp = _psp;
        plugin = _plugin;
        pluginRepo = _pluginRepo;
        votingToken = _votingToken;
        l2VetoReceiver = _l2VetoReceiver;
    }

    /// @notice Executes the full plugin upgrade from Build 1 to Build 2.
    /// @dev Can only be called once. Revokes its own ROOT at the end.
    function upgrade() external {
        if (upgraded) revert AlreadyUpgraded();
        upgraded = true;

        // 1. Register Build 2 in the plugin repo
        pluginRepo.createVersion(1, address(newSetup), bytes(""), bytes(""));

        // 2. Grant temporary permissions for PSP
        _grantPspPermissions();

        // 3. Prepare and apply update
        _prepareAndApplyUpdate();

        // 4. Revoke temporary permissions + own ROOT
        _revokeAllPermissions();
    }

    function _grantPspPermissions() internal {
        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        dao.grant(address(psp), address(this), psp.APPLY_UPDATE_PERMISSION_ID());
        dao.grant(address(plugin), address(psp), plugin.UPGRADE_PLUGIN_PERMISSION_ID());
    }

    function _prepareAndApplyUpdate() internal {
        address[] memory currentHelpers = new address[](1);
        currentHelpers[0] = votingToken;

        (bytes memory initData, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp.prepareUpdate(
            address(dao),
            PluginSetupProcessor.PrepareUpdateParams({
                currentVersionTag: PluginRepo.Tag(1, 1),
                newVersionTag: PluginRepo.Tag(1, 2),
                pluginSetupRepo: pluginRepo,
                setupPayload: IPluginSetup.SetupPayload({
                    plugin: address(plugin),
                    currentHelpers: currentHelpers,
                    data: abi.encode(l2VetoReceiver)
                })
            })
        );

        psp.applyUpdate(
            address(dao),
            PluginSetupProcessor.ApplyUpdateParams({
                plugin: address(plugin),
                pluginSetupRef: PluginSetupRef(PluginRepo.Tag(1, 2), pluginRepo),
                initData: initData,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            })
        );
    }

    function _revokeAllPermissions() internal {
        dao.revoke(address(plugin), address(psp), plugin.UPGRADE_PLUGIN_PERMISSION_ID());
        dao.revoke(address(psp), address(this), psp.APPLY_UPDATE_PERMISSION_ID());
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());

        // Revoke own ROOT
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());
    }
}
