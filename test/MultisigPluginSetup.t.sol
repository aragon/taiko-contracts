// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {Multisig} from "../src/Multisig.sol";
import {MultisigPluginSetup} from "../src/setup/MultisigPluginSetup.sol";
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

contract MultisigPluginSetupTest is Test {
    MultisigPluginSetup public pluginSetup;
    GovernanceERC20 governanceERC20Base;
    GovernanceWrappedERC20 governanceWrappedERC20Base;
    address immutable daoBase = address(new DAO());
    DAO dao;

    // Recycled installation parameters
    Multisig.MultisigSettings multisigSettings;
    address[] members;

    address alice = address(0xa11ce);
    address bob = address(0xb0b);
    address carol = address(0xc4601);
    address dave = address(0xd473);

    error Unimplemented();

    function setUp() public {
        pluginSetup = new MultisigPluginSetup();

        // Default params
        multisigSettings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            destinationProposalDuration: 10 days,
            proposalExpirationPeriod: 15 days
        });

        members = new address[](4);
        members[0] = alice;
        members[1] = bob;
        members[2] = carol;
        members[3] = dave;
    }

    function test_ShouldEncodeInstallationParameters_1() public view {
        // 1
        bytes memory output = pluginSetup.encodeInstallationParameters(members, multisigSettings);

        bytes memory expected =
            hex"00000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000d2f00000000000000000000000000000000000000000000000000000000000013c680000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000a11ce0000000000000000000000000000000000000000000000000000000000000b0b00000000000000000000000000000000000000000000000000000000000c4601000000000000000000000000000000000000000000000000000000000000d473";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldEncodeInstallationParameters_2() public {
        // 2
        multisigSettings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 5 days,
            proposalExpirationPeriod: 33 days
        });

        members = new address[](2);
        members[0] = alice;
        members[1] = bob;

        bytes memory output = pluginSetup.encodeInstallationParameters(members, multisigSettings);
        bytes memory expected =
            hex"00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000006978000000000000000000000000000000000000000000000000000000000002b8180000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000a11ce0000000000000000000000000000000000000000000000000000000000000b0b";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldDecodeInstallationParameters_1() public view {
        // 1
        bytes memory installationParams = pluginSetup.encodeInstallationParameters(members, multisigSettings);

        // Decode
        (address[] memory outMembers, Multisig.MultisigSettings memory outSettings) =
            pluginSetup.decodeInstallationParameters(installationParams);

        assertEq(outMembers.length, 4, "Incorrect length");
        assertEq(outMembers[0], alice, "Incorrect member");
        assertEq(outMembers[1], bob, "Incorrect member");
        assertEq(outMembers[2], carol, "Incorrect member");
        assertEq(outMembers[3], dave, "Incorrect member");

        assertEq(outSettings.onlyListed, true, "Should be true");
        assertEq(outSettings.minApprovals, 3, "Should be 3");
        assertEq(outSettings.destinationProposalDuration, 10 days, "Should be 10 days");
    }

    function test_ShouldDecodeInstallationParameters_2() public {
        // 2
        multisigSettings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            destinationProposalDuration: 5 days,
            proposalExpirationPeriod: 55 days
        });

        members = new address[](2);
        members[0] = alice;
        members[1] = bob;

        bytes memory installationParams = pluginSetup.encodeInstallationParameters(members, multisigSettings);

        // Decode
        (address[] memory outMembers, Multisig.MultisigSettings memory outSettings) =
            pluginSetup.decodeInstallationParameters(installationParams);

        assertEq(outMembers.length, 2, "Incorrect length");
        assertEq(outMembers[0], alice, "Incorrect member");
        assertEq(outMembers[1], bob, "Incorrect member");

        assertEq(outSettings.onlyListed, false, "Should be false");
        assertEq(outSettings.minApprovals, 1, "Should be 1");
        assertEq(outSettings.destinationProposalDuration, 5 days, "Should be 5 days");
    }

    function test_PrepareInstallationReturnsTheProperPermissions() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParameters(members, multisigSettings);

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
        bytes memory installationParams = pluginSetup.encodeInstallationParameters(members, multisigSettings);

        (address _dummyPlugin, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        MultisigPluginSetup.SetupPayload memory _payload =
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
