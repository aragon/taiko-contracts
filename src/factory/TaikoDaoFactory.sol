// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
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
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {createERC1967Proxy} from "@aragon/osx/utils/Proxy.sol";

contract TaikoDaoFactory {
    struct DeploymentSettings {
        // Taiko contract settings
        IVotesUpgradeable tokenAddress;
        address taikoL1ContractAddress;
        address taikoBridgeAddress;
        uint64 l2InactivityPeriod;
        uint64 l2AggregationGracePeriod;
        // Voting settings
        uint32 minVetoRatio;
        uint64 minStdProposalDelay;
        uint16 minStdApprovals;
        uint16 minEmergencyApprovals;
        // OSx contracts
        PluginSetupProcessor pluginSetupProcessor;
        PluginRepoFactory pluginRepoFactory;
        // Token contracts
        GovernanceERC20 governanceErc20Base;
        GovernanceWrappedERC20 governanceErcWrapped20Base;
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

    DeploymentSettings settings;
    Deployment deployment;

    // Implementations
    address immutable DAO_BASE = address(new DAO());

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _settings The settings of the one-time deployment.
    constructor(DeploymentSettings memory _settings) {
        settings = _settings;

        deploy();
    }

    function deploy() internal {
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
        dao.grant(address(dao), address(settings.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

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

        dao.revoke(address(dao), address(settings.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

        // DEPLOY OTHER CONTRACTS
        deployment.publicKeyRegistry = deployPublicKeyRegistry();

        // REMOVE THIS CONTRACT AS OWNER
        dropRootPermission(deployment.dao);
    }

    function prepareDao() internal returns (DAO dao) {
        dao = DAO(
            payable(
                createERC1967Proxy(
                    address(DAO_BASE),
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
        // Deploy plugin setup
        MultisigPluginSetup pluginSetup = new MultisigPluginSetup();

        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(settings.pluginRepoFactory).createPluginRepoWithFirstVersion(
            settings.stdMultisigEnsDomain, address(pluginSetup), msg.sender, "", ""
        );

        bytes memory settingsData = pluginSetup.encodeInstallationParameters(
            settings.multisigMembers,
            Multisig.MultisigSettings(
                true, // onlyListed
                settings.minStdApprovals,
                settings.minStdProposalDelay // destination minDuration
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
        // Deploy plugin setup
        EmergencyMultisigPluginSetup pluginSetup = new EmergencyMultisigPluginSetup();

        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(settings.pluginRepoFactory).createPluginRepoWithFirstVersion(
            settings.emergencyMultisigEnsDomain, address(pluginSetup), msg.sender, "", ""
        );

        bytes memory settingsData = pluginSetup.encodeInstallationParameters(
            settings.multisigMembers,
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
        // Deploy plugin setup
        OptimisticTokenVotingPluginSetup pluginSetup =
            new OptimisticTokenVotingPluginSetup(settings.governanceErc20Base, settings.governanceErcWrapped20Base);

        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(settings.pluginRepoFactory).createPluginRepoWithFirstVersion(
            settings.optimisticTokenVotingEnsDomain, address(pluginSetup), msg.sender, "", ""
        );

        // Plugin settings
        bytes memory settingsData;
        {
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory votingSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings(
                settings.minVetoRatio,
                0, // minDuration (the condition contract will enforce it)
                settings.l2InactivityPeriod,
                settings.l2AggregationGracePeriod
            );

            OptimisticTokenVotingPluginSetup.TokenSettings memory tokenSettings =
                OptimisticTokenVotingPluginSetup.TokenSettings(address(settings.tokenAddress), "", "");

            GovernanceERC20.MintSettings memory mintSettings =
                GovernanceERC20.MintSettings(new address[](0), new uint256[](0));

            settingsData = pluginSetup.encodeInstallationParams(
                OptimisticTokenVotingPluginSetup.InstallationParameters(
                    votingSettings,
                    tokenSettings,
                    mintSettings,
                    settings.taikoL1ContractAddress,
                    settings.taikoBridgeAddress,
                    settings.minStdProposalDelay,
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
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0] = IDAO.Action(
            address(dao),
            0,
            abi.encodeCall(
                PluginSetupProcessor.applyInstallation,
                (
                    address(dao),
                    PluginSetupProcessor.ApplyInstallationParams(
                        PluginSetupRef(PluginRepo.Tag(1, 1), pluginRepo),
                        plugin,
                        preparedSetupData.permissions,
                        hashHelpers(preparedSetupData.helpers)
                    )
                )
            )
        );
        dao.execute(bytes32(uint256(0x1)), actions, 0);
    }

    function dropRootPermission(DAO dao) internal {
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
