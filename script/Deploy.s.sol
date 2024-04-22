// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {VmSafe} from "forge-std/Vm.sol";
import {Script} from "forge-std/Script.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {OptimisticTokenVotingPluginSetup} from "../src/setup/OptimisticTokenVotingPluginSetup.sol";
import {MultisigPluginSetup} from "../src/setup/MultisigPluginSetup.sol";
import {EmergencyMultisigPluginSetup} from "../src/setup/EmergencyMultisigPluginSetup.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {Multisig} from "@aragon/osx/plugins/governance/multisig/Multisig.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {createERC1967Proxy} from "@aragon/osx/utils/Proxy.sol";

contract Deploy is Script {
    DAO daoImplementation;
    Multisig multisigImplementation;

    address governanceERC20Base;
    address governanceWrappedERC20Base;
    PluginSetupProcessor pluginSetupProcessor;
    address pluginRepoFactory;
    address tokenAddress;
    address[] multisigMembers;

    uint16 minStdApprovals;
    uint16 minEmergencyApprovals;

    constructor() {
        // Implementations
        daoImplementation = new DAO();
        multisigImplementation = new Multisig();

        governanceERC20Base = vm.envAddress("GOVERNANCE_ERC20_BASE");
        governanceWrappedERC20Base = vm.envAddress(
            "GOVERNANCE_WRAPPED_ERC20_BASE"
        );
        pluginSetupProcessor = PluginSetupProcessor(
            vm.envAddress("PLUGIN_SETUP_PROCESSOR")
        );
        pluginRepoFactory = vm.envAddress("PLUGIN_REPO_FACTORY");
        tokenAddress = vm.envAddress("TOKEN_ADDRESS");

        minStdApprovals = uint16(vm.envUint("MIN_STD_APPROVALS"));
        minEmergencyApprovals = uint16(vm.envUint("MIN_EMERGENCY_APPROVALS"));

        // JSON list of members
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/utils/members.json");
        string memory json = vm.readFile(path);
        multisigMembers = vm.parseJsonAddressArray(json, "$.addresses");
    }

    function run() public {
        // Deploy a raw DAO
        DAO dao = prepareDao();

        // Prepare plugins
        (
            address p1,
            PluginRepo pr1,
            IPluginSetup.PreparedSetupData memory preparedSetupData1
        ) = prepareMultisig(dao);

        (
            address p2,
            PluginRepo pr2,
            IPluginSetup.PreparedSetupData memory preparedSetupData2
        ) = prepareEmergencyMultisig(dao);

        (
            address p3,
            PluginRepo pr3,
            IPluginSetup.PreparedSetupData memory preparedSetupData3
        ) = prepareOptimisticTokenVoting(dao, p1, p2);

        // Apply installations
        dao.grant(
            address(dao),
            address(pluginSetupProcessor),
            dao.ROOT_PERMISSION_ID()
        );

        applyPluginInstallation(dao, p1, pr1, preparedSetupData1);
        applyPluginInstallation(dao, p2, pr2, preparedSetupData2);
        applyPluginInstallation(dao, p3, pr3, preparedSetupData3);

        dao.revoke(
            address(dao),
            address(pluginSetupProcessor),
            dao.ROOT_PERMISSION_ID()
        );

        // Remove ourselves as root

        dao.revoke(address(dao), getDeployerWallet(), dao.ROOT_PERMISSION_ID());
    }

    // Helpers

    function prepareDeployerWallet() internal {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // vm.stopBroadcast();
    }

    function getDeployerWallet() private returns (address) {
        VmSafe.Wallet memory wallet = vm.createWallet(
            vm.envUint("PRIVATE_KEY")
        );

        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encode(wallet.publicKeyX, wallet.publicKeyY)
                        )
                    )
                )
            );
    }

    function prepareDao() internal returns (DAO dao) {
        dao = DAO(
            payable(
                createERC1967Proxy(
                    address(daoImplementation),
                    abi.encodeCall(
                        DAO.initialize,
                        (
                            "", // Metadata URI
                            getDeployerWallet(),
                            address(0x0),
                            "" // DAO URI
                        )
                    )
                )
            )
        );
    }

    function prepareMultisig(
        DAO dao
    )
        internal
        returns (address, PluginRepo, IPluginSetup.PreparedSetupData memory)
    {
        // Deploy plugin setup
        MultisigPluginSetup pluginSetup = new MultisigPluginSetup(
            multisigImplementation
        );

        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                "ens-of-the-multisig",
                address(pluginSetup),
                msg.sender,
                "0x",
                "0x"
            );

        bytes memory settingsData = pluginSetup.encodeInstallationParameters(
            multisigMembers,
            Multisig.MultisigSettings(
                true, // onlyListed
                minStdApprovals // minAppovals
            )
        );

        (
            address plugin,
            IPluginSetup.PreparedSetupData memory preparedSetupData
        ) = pluginSetupProcessor.prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(
                        PluginRepo.Tag(1, 1),
                        PluginRepo(pluginRepo)
                    ),
                    settingsData
                )
            );

        return (plugin, pluginRepo, preparedSetupData);
    }

    function prepareEmergencyMultisig(
        DAO dao
    )
        internal
        returns (address, PluginRepo, IPluginSetup.PreparedSetupData memory)
    {
        // Deploy plugin setup
        EmergencyMultisigPluginSetup pluginSetup = new EmergencyMultisigPluginSetup(
                multisigImplementation
            );

        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                "ens-of-the-emergency-multisig",
                address(pluginSetup),
                msg.sender,
                "0x",
                "0x"
            );

        bytes memory settingsData = pluginSetup.encodeInstallationParameters(
            multisigMembers,
            Multisig.MultisigSettings(
                true, // onlyListed
                minEmergencyApprovals // minAppovals
            )
        );

        (
            address plugin,
            IPluginSetup.PreparedSetupData memory preparedSetupData
        ) = pluginSetupProcessor.prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(
                        PluginRepo.Tag(1, 1),
                        PluginRepo(pluginRepo)
                    ),
                    settingsData
                )
            );

        return (plugin, pluginRepo, preparedSetupData);
    }

    function prepareOptimisticTokenVoting(
        DAO dao,
        address stdProposer,
        address emergencyProposer
    )
        internal
        returns (address, PluginRepo, IPluginSetup.PreparedSetupData memory)
    {
        // Deploy plugin setup
        OptimisticTokenVotingPluginSetup pluginSetup = new OptimisticTokenVotingPluginSetup(
                GovernanceERC20(governanceERC20Base),
                GovernanceWrappedERC20(governanceWrappedERC20Base)
            );

        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                "ens-of-the-optimistic-token-voting",
                address(pluginSetup),
                msg.sender,
                "0x",
                "0x"
            );

        // Plugin settings
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory votingSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings(
                    200000, // minVetoRatio - 20%
                    0, // minDuration (the condition will enforce it)
                    0 // minProposerVotingPower
                );

        OptimisticTokenVotingPluginSetup.TokenSettings
            memory tokenSettings = OptimisticTokenVotingPluginSetup
                .TokenSettings(tokenAddress, "", "");

        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20
            .MintSettings(new address[](0), new uint256[](0));

        bytes memory settingsData = pluginSetup.encodeInstallationParams(
            votingSettings,
            tokenSettings,
            mintSettings,
            stdProposer,
            emergencyProposer
        );

        (
            address plugin,
            IPluginSetup.PreparedSetupData memory preparedSetupData
        ) = pluginSetupProcessor.prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(
                        PluginRepo.Tag(1, 1),
                        PluginRepo(pluginRepo)
                    ),
                    settingsData
                )
            );

        return (plugin, pluginRepo, preparedSetupData);
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
}
