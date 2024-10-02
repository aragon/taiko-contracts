// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {EmergencyMultisig} from "../src/EmergencyMultisig.sol";
import {Multisig} from "../src/Multisig.sol";
import {EmergencyMultisigPluginSetup} from "../src/setup/EmergencyMultisigPluginSetup.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ITaikoL1} from "../src/adapted-dependencies/ITaikoL1.sol";

contract EmergencyMultisigPluginSetupTest is Test {
    EmergencyMultisigPluginSetup public pluginSetup;
    GovernanceERC20 governanceERC20Base;
    GovernanceWrappedERC20 governanceWrappedERC20Base;
    address immutable daoBase = address(new DAO());
    address immutable stdMultisigBase = address(new Multisig());
    DAO dao;

    // Recycled installation parameters
    EmergencyMultisig.MultisigSettings eMultisigSettings;
    address[] stdMembers;
    Multisig stdMultisig;

    address alice = address(0xa11ce);
    address bob = address(0xb0b);
    address carol = address(0xc4601);
    address dave = address(0xd473);

    error Unimplemented();

    function setUp() public {
        pluginSetup = new EmergencyMultisigPluginSetup();

        // Address list source (std multisig)
        stdMembers = new address[](4);
        stdMembers[0] = alice;
        stdMembers[1] = bob;
        stdMembers[2] = carol;
        stdMembers[3] = dave;
        Multisig.MultisigSettings memory stdSettings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            destinationProposalDuration: 10 days,
            proposalExpirationPeriod: 15 days
        });
        stdMultisig = Multisig(
            createProxyAndCall(
                stdMultisigBase, abi.encodeCall(Multisig.initialize, (IDAO(dao), stdMembers, stdSettings))
            )
        );

        // Default params
        eMultisigSettings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            addresslistSource: stdMultisig,
            proposalExpirationPeriod: 15 days
        });
    }

    function test_ShouldEncodeInstallationParameters_1() public view {
        // 1
        bytes memory output = pluginSetup.encodeInstallationParameters(eMultisigSettings);

        bytes memory expected =
            hex"000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000030000000000000000000000005991a2df15a8f6a256d3ec51e99254cd3fb576a9000000000000000000000000000000000000000000000000000000000013c680";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldEncodeInstallationParameters_2() public {
        // 2
        stdMembers = new address[](2);
        stdMembers[0] = alice;
        stdMembers[1] = bob;
        Multisig.MultisigSettings memory stdSettings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 10 days,
            proposalExpirationPeriod: 17 days
        });
        stdMultisig = Multisig(
            createProxyAndCall(
                stdMultisigBase, abi.encodeCall(Multisig.initialize, (IDAO(dao), stdMembers, stdSettings))
            )
        );

        eMultisigSettings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            addresslistSource: stdMultisig,
            proposalExpirationPeriod: 17 days
        });

        bytes memory output = pluginSetup.encodeInstallationParameters(eMultisigSettings);
        bytes memory expected =
            hex"00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000c7183455a4c133ae270771860664b6b7ec320bb10000000000000000000000000000000000000000000000000000000000166980";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldDecodeInstallationParameters_1() public view {
        // 1
        bytes memory installationParams = pluginSetup.encodeInstallationParameters(eMultisigSettings);

        // Decode
        (EmergencyMultisig.MultisigSettings memory outSettings) =
            pluginSetup.decodeInstallationParameters(installationParams);

        assertEq(outSettings.onlyListed, true, "Should be true");
        assertEq(outSettings.minApprovals, 3, "Should be 3");
        assertEq(
            address(outSettings.addresslistSource),
            address(eMultisigSettings.addresslistSource),
            "Incorrect address list source"
        );
    }

    function test_ShouldDecodeInstallationParameters_2() public {
        // 2

        stdMembers = new address[](2);
        stdMembers[0] = alice;
        stdMembers[1] = bob;
        Multisig.MultisigSettings memory stdSettings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 10 days,
            proposalExpirationPeriod: 5 days
        });
        stdMultisig = Multisig(
            createProxyAndCall(
                stdMultisigBase, abi.encodeCall(Multisig.initialize, (IDAO(dao), stdMembers, stdSettings))
            )
        );
        eMultisigSettings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            addresslistSource: stdMultisig,
            proposalExpirationPeriod: 5 days
        });

        bytes memory installationParams = pluginSetup.encodeInstallationParameters(eMultisigSettings);

        // Decode
        (EmergencyMultisig.MultisigSettings memory outSettings) =
            pluginSetup.decodeInstallationParameters(installationParams);

        assertEq(outSettings.onlyListed, false, "Should be false");
        assertEq(outSettings.minApprovals, 1, "Should be 1");
        assertEq(address(outSettings.addresslistSource), address(stdMultisig), "Incorrect address list source");
    }

    function test_PrepareInstallationReturnsTheProperPermissions() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParameters(eMultisigSettings);

        (address _plugin, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        assertEq(_plugin != address(0), true, "Plugin address should not be zero");
        assertEq(_preparedSetupData.helpers.length, 0, "Zero helpers expected");
        assertEq(
            _preparedSetupData.permissions.length,
            2, // permissions
            "Incorrect permission length"
        );
        // 1
        assertEq(
            uint256(_preparedSetupData.permissions[0].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[0].where, _plugin, "Incorrect where");
        assertEq(_preparedSetupData.permissions[0].who, address(dao), "Incorrect who");
        assertEq(_preparedSetupData.permissions[0].condition, address(0), "Incorrect condition");
        assertEq(
            _preparedSetupData.permissions[0].permissionId,
            keccak256("UPDATE_MULTISIG_SETTINGS_PERMISSION"),
            "Incorrect permission id"
        );
        // 2
        assertEq(_preparedSetupData.permissions[1].where, _plugin, "Incorrect where");
        assertEq(_preparedSetupData.permissions[1].who, address(dao), "Incorrect who");
        assertEq(_preparedSetupData.permissions[1].condition, address(0), "Incorrect condition");
        assertEq(
            _preparedSetupData.permissions[1].permissionId,
            keccak256("UPGRADE_PLUGIN_PERMISSION"),
            "Incorrect permission id"
        );
    }

    function test_PrepareUninstallationReturnsTheProperPermissions_1() public {
        // Prepare a dummy install
        bytes memory installationParams = pluginSetup.encodeInstallationParameters(eMultisigSettings);

        (address _dummyPlugin, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        EmergencyMultisigPluginSetup.SetupPayload memory _payload =
            IPluginSetup.SetupPayload({plugin: _dummyPlugin, currentHelpers: _preparedSetupData.helpers, data: hex""});

        // Check uninstall
        PermissionLib.MultiTargetPermission[] memory _permissionChanges =
            pluginSetup.prepareUninstallation(address(dao), _payload);

        assertEq(_permissionChanges.length, 2, "Incorrect permission changes length");
        // 1
        assertEq(
            uint256(_permissionChanges[0].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[0].where, _dummyPlugin);
        assertEq(_permissionChanges[0].who, address(dao));
        assertEq(_permissionChanges[0].condition, address(0));
        assertEq(_permissionChanges[0].permissionId, keccak256("UPDATE_MULTISIG_SETTINGS_PERMISSION"));
        // 2
        assertEq(
            uint256(_permissionChanges[1].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[1].where, _dummyPlugin);
        assertEq(_permissionChanges[1].who, address(dao));
        assertEq(_permissionChanges[1].condition, address(0));
        assertEq(_permissionChanges[1].permissionId, keccak256("UPGRADE_PLUGIN_PERMISSION"));
    }

    function test_ImplementationIsNotEmpty() public view {
        assertEq(pluginSetup.implementation() != address(0), true);
    }

    // HELPERS
    function createProxyAndCall(address _logic, bytes memory _data) private returns (address) {
        return address(new ERC1967Proxy(_logic, _data));
    }
}
