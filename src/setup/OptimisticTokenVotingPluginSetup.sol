// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetup, IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {IGovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/IGovernanceWrappedERC20.sol";
import {OptimisticTokenVotingPlugin} from "../OptimisticTokenVotingPlugin.sol";
import {StandardProposalCondition} from "../conditions/StandardProposalCondition.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ITaikoL1} from "../adapted-dependencies/ITaikoL1.sol";

/// @title OptimisticTokenVotingPluginSetup
/// @author Aragon Association - 2022-2023
/// @notice The setup contract of the `OptimisticTokenVoting` plugin.
/// @custom:security-contact sirt@aragon.org
contract OptimisticTokenVotingPluginSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;

    /// @notice The address of the `OptimisticTokenVotingPlugin` base contract.
    OptimisticTokenVotingPlugin private immutable optimisticTokenVotingPluginBase;

    /// @notice The address of the `GovernanceERC20` base contract.
    address public immutable governanceERC20Base;

    /// @notice The address of the `GovernanceWrappedERC20` base contract.
    address public immutable governanceWrappedERC20Base;

    /// @notice The token settings struct.
    /// @param addr The token address. If this is `address(0)`, a new `GovernanceERC20` token is deployed. If not, the existing token is wrapped as an `GovernanceWrappedERC20`.
    /// @param name The token name. This parameter is only relevant if the token address is `address(0)`.
    /// @param symbol The token symbol. This parameter is only relevant if the token address is `address(0)`.
    struct TokenSettings {
        address addr;
        string name;
        string symbol;
    }

    struct InstallationParameters {
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings votingSettings;
        TokenSettings tokenSettings;
        // only used for GovernanceERC20 (when token is not passed)
        GovernanceERC20.MintSettings mintSettings;
        address taikoL1;
        address taikoBridge;
        uint64 stdProposalMinDuration;
        address stdProposer;
        address emergencyProposer;
    }

    /// @notice Thrown if token address is passed which is not a token.
    /// @param token The token address
    error TokenNotContract(address token);

    /// @notice Thrown if token address is not ERC20.
    /// @param token The token address
    error TokenNotERC20(address token);

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice The contract constructor deploying the plugin implementation contract and receiving the governance token base contracts to clone from.
    /// @param _governanceERC20Base The base `GovernanceERC20` contract to create clones from.
    /// @param _governanceWrappedERC20Base The base `GovernanceWrappedERC20` contract to create clones from.
    constructor(GovernanceERC20 _governanceERC20Base, GovernanceWrappedERC20 _governanceWrappedERC20Base) {
        optimisticTokenVotingPluginBase = new OptimisticTokenVotingPlugin();
        governanceERC20Base = address(_governanceERC20Base);
        governanceWrappedERC20Base = address(_governanceWrappedERC20Base);
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(address _dao, bytes calldata _installParameters)
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        // Decode `_installParameters` to extract the params needed for deploying and initializing `OptimisticTokenVoting` plugin,
        // and the required helpers
        InstallationParameters memory installationParams = decodeInstallationParams(_installParameters);

        address token = installationParams.tokenSettings.addr;

        // Prepare helpers.
        address[] memory helpers = new address[](1);

        if (token != address(0x0)) {
            if (!token.isContract()) {
                revert TokenNotContract(token);
            } else if (!_supportsErc20(token)) {
                revert TokenNotERC20(token);
            }

            if (!_supportsIVotes(token) && !_supportsIGovernanceWrappedERC20(token)) {
                // Wrap the token
                token = governanceWrappedERC20Base.clone();

                // User already has a token. We need to wrap it in
                // GovernanceWrappedERC20 in order to make the token
                // include governance functionality.
                GovernanceWrappedERC20(token).initialize(
                    IERC20Upgradeable(installationParams.tokenSettings.addr),
                    installationParams.tokenSettings.name,
                    installationParams.tokenSettings.symbol
                );
            }
        } else {
            // Create a brand new token
            token = governanceERC20Base.clone();
            GovernanceERC20(token).initialize(
                IDAO(_dao),
                installationParams.tokenSettings.name,
                installationParams.tokenSettings.symbol,
                installationParams.mintSettings
            );
        }

        helpers[0] = token;

        // Prepare and deploy plugin proxy.
        plugin = createERC1967Proxy(
            address(optimisticTokenVotingPluginBase),
            abi.encodeCall(
                OptimisticTokenVotingPlugin.initialize,
                (
                    IDAO(_dao),
                    installationParams.votingSettings,
                    IVotesUpgradeable(token),
                    installationParams.taikoL1,
                    installationParams.taikoBridge
                )
            )
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[] memory permissions =
            new PermissionLib.MultiTargetPermission[](installationParams.tokenSettings.addr != address(0) ? 5 : 6);

        // Request the permissions to be granted

        // The DAO can update the plugin settings
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: optimisticTokenVotingPluginBase.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        });

        // The DAO can upgrade the plugin implementation
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: optimisticTokenVotingPluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        // The plugin can make the DAO execute actions
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });
        {
            // Deploy the Std proposal condition
            StandardProposalCondition stdProposalCondition =
                new StandardProposalCondition(address(_dao), installationParams.stdProposalMinDuration);

            // Proposer plugins can create proposals
            permissions[3] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: plugin,
                who: installationParams.stdProposer,
                condition: address(stdProposalCondition),
                permissionId: optimisticTokenVotingPluginBase.PROPOSER_PERMISSION_ID()
            });
        }
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: installationParams.emergencyProposer,
            condition: PermissionLib.NO_CONDITION,
            permissionId: optimisticTokenVotingPluginBase.PROPOSER_PERMISSION_ID()
        });

        if (installationParams.tokenSettings.addr == address(0x0)) {
            // The DAO can mint ERC20 tokens
            permissions[5] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: token,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: GovernanceERC20(token).MINT_PERMISSION_ID()
            });
        }

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(address _dao, SetupPayload calldata _payload)
        external
        view
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        // Prepare permissions.
        uint256 helperLength = _payload.currentHelpers.length;
        if (helperLength != 1) {
            revert WrongHelpersArrayLength({length: helperLength});
        }

        // token can be either GovernanceERC20, GovernanceWrappedERC20, or IVotesUpgradeable, which
        // does not follow the GovernanceERC20 and GovernanceWrappedERC20 standard.
        address token = _payload.currentHelpers[0];

        bool isGovernanceERC20 =
            _supportsErc20(token) && _supportsIVotes(token) && !_supportsIGovernanceWrappedERC20(token);

        permissions = new PermissionLib.MultiTargetPermission[](isGovernanceERC20 ? 4 : 3);

        // Set permissions to be Revoked.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: optimisticTokenVotingPluginBase.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: optimisticTokenVotingPluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        // Note: It no longer matters if proposers can still create proposals

        // Revocation of permission is necessary only if the deployed token is GovernanceERC20,
        // as GovernanceWrapped does not possess this permission. Only return the following
        // if it's type of GovernanceERC20, otherwise revoking this permission wouldn't have any effect.
        if (isGovernanceERC20) {
            permissions[3] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Revoke,
                where: token,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: GovernanceERC20(token).MINT_PERMISSION_ID()
            });
        }
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(optimisticTokenVotingPluginBase);
    }

    /// @notice Encodes the given installation parameters into a byte array
    function encodeInstallationParams(InstallationParameters memory installationParams)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(installationParams);
    }

    /// @notice Decodes the given byte array into the original installation parameters
    function decodeInstallationParams(bytes memory _data)
        public
        pure
        returns (InstallationParameters memory installationParams)
    {
        installationParams = abi.decode(_data, (InstallationParameters));
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20 token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @param token The token address
    function _supportsErc20(address token) private view returns (bool) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeCall(IERC20Upgradeable.balanceOf, (address(this))));
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(abi.encodeCall(IERC20Upgradeable.totalSupply, ()));
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(abi.encodeCall(IERC20Upgradeable.allowance, (address(this), address(this))));
        if (!success || data.length != 0x20) return false;

        return true;
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20 token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @param token The token address
    function _supportsIVotes(address token) private view returns (bool) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeCall(IVotesUpgradeable.getVotes, (address(this))));
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(abi.encodeCall(IVotesUpgradeable.getPastVotes, (address(this), 0)));
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(abi.encodeCall(IVotesUpgradeable.getPastTotalSupply, (0)));
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(abi.encodeCall(IVotesUpgradeable.delegates, (address(this))));
        if (!success || data.length != 0x20) return false;

        return true;
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20 token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @param token The token address
    function _supportsIGovernanceWrappedERC20(address token) private view returns (bool) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeCall(IERC165.supportsInterface, (bytes4(0))));
        if (!success || data.length != 0x20) return false;

        return IERC165(token).supportsInterface(type(IGovernanceWrappedERC20).interfaceId);
    }
}
