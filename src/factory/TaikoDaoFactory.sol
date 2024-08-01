// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {Multisig} from "../Multisig.sol";
import {EmergencyMultisig} from "../EmergencyMultisig.sol";
import {PublicKeyRegistry} from "../PublicKeyRegistry.sol";
import {OptimisticTokenVotingPlugin} from "../OptimisticTokenVotingPlugin.sol";
import {OptimisticTokenVotingPluginSetup} from "../setup/OptimisticTokenVotingPluginSetup.sol";
import {MultisigPluginSetup} from "../setup/MultisigPluginSetup.sol";
import {EmergencyMultisigPluginSetup} from "../setup/EmergencyMultisigPluginSetup.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {createERC1967Proxy} from "@aragon/osx/utils/Proxy.sol";

contract TaikoDaoFactory {
    struct DeploymentSettings {
        // Taiko contract settings
        IVotesUpgradeable tokenAddress;
        address taikoL1ContractAddress;
        address taikoBridgeAddress;
        uint64 l2InactivityPeriod;
        uint64 l2AggregationGracePeriod;
        bool skipL2;
        // Voting settings
        uint32 minVetoRatio;
        uint64 minStdProposalDuration;
        uint16 minStdApprovals;
        uint16 minEmergencyApprovals;
        // OSx contracts
        address osxDaoFactory;
        PluginSetupProcessor pluginSetupProcessor;
        PluginRepoFactory pluginRepoFactory;
        // Plugin setup's
        MultisigPluginSetup multisigPluginSetup;
        EmergencyMultisigPluginSetup emergencyMultisigPluginSetup;
        OptimisticTokenVotingPluginSetup optimisticTokenVotingPluginSetup;
        // Multisig
        address[] multisigMembers;
        // ENS
        string stdMultisigEnsDomain;
        string emergencyMultisigEnsDomain;
        string optimisticTokenVotingEnsDomain;
    }

    struct Deployment {
        DAO dao;
        // Plugins
        Multisig multisigPlugin;
        EmergencyMultisig emergencyMultisigPlugin;
        OptimisticTokenVotingPlugin optimisticTokenVotingPlugin;
        // Plugin repo's
        PluginRepo multisigPluginRepo;
        PluginRepo emergencyMultisigPluginRepo;
        PluginRepo optimisticTokenVotingPluginRepo;
        // Other
        PublicKeyRegistry publicKeyRegistry;
    }

    /// @notice Thrown when attempting to call deployOnce() when the DAO is already deployed.
    error AlreadyDeployed();

    DeploymentSettings settings;
    Deployment deployment;

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _settings The settings of the one-time deployment.
    constructor(DeploymentSettings memory _settings) {
        settings = _settings;
    }

    function deployOnce() public {
        if (address(deployment.dao) != address(0)) revert AlreadyDeployed();

        IPluginSetup.PreparedSetupData memory preparedMultisigSetupData;
        IPluginSetup.PreparedSetupData memory preparedEmergencyMultisigSetupData;
        IPluginSetup.PreparedSetupData memory preparedOptimisticSetupData;

        // DEPLOY THE DAO (The factory is the interim owner)
        DAO dao = prepareDao();
        deployment.dao = dao;

        // DEPLOY THE PLUGINS
        (deployment.multisigPlugin, deployment.multisigPluginRepo, preparedMultisigSetupData) = prepareMultisig(dao);

        (deployment.emergencyMultisigPlugin, deployment.emergencyMultisigPluginRepo, preparedEmergencyMultisigSetupData)
        = prepareEmergencyMultisig(dao, deployment.multisigPlugin);

        (
            deployment.optimisticTokenVotingPlugin,
            deployment.optimisticTokenVotingPluginRepo,
            preparedOptimisticSetupData
        ) = prepareOptimisticTokenVoting(
            dao, address(deployment.multisigPlugin), address(deployment.emergencyMultisigPlugin)
        );

        // APPLY THE INSTALLATIONS
        grantApplyInstallationPermissions(dao);

        applyPluginInstallation(
            dao, address(deployment.multisigPlugin), deployment.multisigPluginRepo, preparedMultisigSetupData
        );
        applyPluginInstallation(
            dao,
            address(deployment.emergencyMultisigPlugin),
            deployment.emergencyMultisigPluginRepo,
            preparedEmergencyMultisigSetupData
        );
        applyPluginInstallation(
            dao,
            address(deployment.optimisticTokenVotingPlugin),
            deployment.optimisticTokenVotingPluginRepo,
            preparedOptimisticSetupData
        );

        revokeApplyInstallationPermissions(dao);

        // REMOVE THIS CONTRACT AS OWNER
        revokeOwnerPermission(deployment.dao);

        // DEPLOY OTHER CONTRACTS
        deployment.publicKeyRegistry = deployPublicKeyRegistry();
    }

    function prepareDao() internal returns (DAO dao) {
        address daoBase = DAOFactory(settings.osxDaoFactory).daoBase();

        dao = DAO(
            payable(
                createERC1967Proxy(
                    address(daoBase),
                    abi.encodeCall(
                        DAO.initialize,
                        (
                            "", // Metadata URI
                            address(this),
                            address(0x0), // Trusted forwarder
                            "" // DAO URI
                        )
                    )
                )
            )
        );
    }

    function prepareMultisig(DAO dao) internal returns (Multisig, PluginRepo, IPluginSetup.PreparedSetupData memory) {
        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(settings.pluginRepoFactory).createPluginRepoWithFirstVersion(
            settings.stdMultisigEnsDomain, address(settings.multisigPluginSetup), msg.sender, " ", " "
        );

        bytes memory settingsData = settings.multisigPluginSetup.encodeInstallationParameters(
            settings.multisigMembers,
            Multisig.MultisigSettings(
                true, // onlyListed
                settings.minStdApprovals,
                settings.minStdProposalDuration // destination minDuration
            )
        );

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = settings
            .pluginSetupProcessor
            .prepareInstallation(
            address(dao),
            PluginSetupProcessor.PrepareInstallationParams(
                PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(pluginRepo)), settingsData
            )
        );

        return (Multisig(plugin), pluginRepo, preparedSetupData);
    }

    function prepareEmergencyMultisig(DAO dao, Addresslist multisigPlugin)
        internal
        returns (EmergencyMultisig, PluginRepo, IPluginSetup.PreparedSetupData memory)
    {
        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(settings.pluginRepoFactory).createPluginRepoWithFirstVersion(
            settings.emergencyMultisigEnsDomain, address(settings.emergencyMultisigPluginSetup), msg.sender, " ", " "
        );

        bytes memory settingsData = settings.emergencyMultisigPluginSetup.encodeInstallationParameters(
            EmergencyMultisig.MultisigSettings(
                true, // onlyListed
                settings.minEmergencyApprovals, // minAppovals
                Addresslist(multisigPlugin)
            )
        );

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = settings
            .pluginSetupProcessor
            .prepareInstallation(
            address(dao),
            PluginSetupProcessor.PrepareInstallationParams(
                PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(pluginRepo)), settingsData
            )
        );

        return (EmergencyMultisig(plugin), pluginRepo, preparedSetupData);
    }

    function prepareOptimisticTokenVoting(DAO dao, address stdProposer, address emergencyProposer)
        internal
        returns (OptimisticTokenVotingPlugin, PluginRepo, IPluginSetup.PreparedSetupData memory)
    {
        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(settings.pluginRepoFactory).createPluginRepoWithFirstVersion(
            settings.optimisticTokenVotingEnsDomain,
            address(settings.optimisticTokenVotingPluginSetup),
            msg.sender,
            " ",
            " "
        );

        // Plugin settings
        bytes memory settingsData;
        {
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory votingSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings(
                settings.minVetoRatio,
                0, // minDuration (the condition contract will enforce it)
                settings.l2InactivityPeriod,
                settings.l2AggregationGracePeriod,
                settings.skipL2
            );

            OptimisticTokenVotingPluginSetup.TokenSettings memory existingTokenSettings =
                OptimisticTokenVotingPluginSetup.TokenSettings(address(settings.tokenAddress), "Taiko", "TKO");
            GovernanceERC20.MintSettings memory unusedMintSettings =
                GovernanceERC20.MintSettings(new address[](0), new uint256[](0));

            settingsData = settings.optimisticTokenVotingPluginSetup.encodeInstallationParams(
                OptimisticTokenVotingPluginSetup.InstallationParameters(
                    votingSettings,
                    existingTokenSettings,
                    unusedMintSettings,
                    settings.taikoL1ContractAddress,
                    settings.taikoBridgeAddress,
                    settings.minStdProposalDuration,
                    stdProposer,
                    emergencyProposer
                )
            );
        }

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = settings
            .pluginSetupProcessor
            .prepareInstallation(
            address(dao),
            PluginSetupProcessor.PrepareInstallationParams(
                PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(pluginRepo)), settingsData
            )
        );

        return (OptimisticTokenVotingPlugin(plugin), pluginRepo, preparedSetupData);
    }

    function deployPublicKeyRegistry() internal returns (PublicKeyRegistry) {
        return new PublicKeyRegistry();
    }

    function applyPluginInstallation(
        DAO dao,
        address plugin,
        PluginRepo pluginRepo,
        IPluginSetup.PreparedSetupData memory preparedSetupData
    ) internal {
        settings.pluginSetupProcessor.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams(
                PluginSetupRef(PluginRepo.Tag(1, 1), pluginRepo),
                plugin,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );
    }

    function grantApplyInstallationPermissions(DAO dao) internal {
        // The PSP can manage permissions on the new DAO
        dao.grant(address(dao), address(settings.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

        // This factory can call applyInstallation() on the PSP
        dao.grant(
            address(settings.pluginSetupProcessor),
            address(this),
            settings.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );
    }

    function revokeApplyInstallationPermissions(DAO dao) internal {
        // Revoking the permission for the factory to call applyInstallation() on the PSP
        dao.revoke(
            address(settings.pluginSetupProcessor),
            address(this),
            settings.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );

        // Revoke the PSP permission to manage permissions on the new DAO
        dao.revoke(address(dao), address(settings.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());
    }

    function revokeOwnerPermission(DAO dao) internal {
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());
    }

    // Getters

    function getSettings() public view returns (DeploymentSettings memory) {
        return settings;
    }

    function getDeployment() public view returns (Deployment memory) {
        return deployment;
    }
}
