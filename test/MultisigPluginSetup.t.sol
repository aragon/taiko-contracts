// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {Multisig} from "../src/Multisig.sol";
import {MultisigPluginSetup} from "../src/setup/MultisigPluginSetup.sol";
import {
    SignerList,
    UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID,
    UPDATE_SIGNER_LIST_PERMISSION_ID
} from "../src/SignerList.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MultisigPluginSetupTest is AragonTest {
    MultisigPluginSetup public pluginSetup;
    address immutable daoBase = address(new DAO());
    address immutable signerListBase = address(new SignerList());
    DAO dao;

    // Recycled installation parameters
    Multisig.MultisigSettings multisigSettings;
    address[] signers;
    SignerList signerList;

    function setUp() public {
        DaoBuilder builder = new DaoBuilder();
        (dao,,,,, signerList,,) = builder.withMultisigMember(alice).withMultisigMember(bob).withMultisigMember(carol)
            .withMultisigMember(david).build();

        pluginSetup = new MultisigPluginSetup();

        // Default params
        multisigSettings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            destinationProposalDuration: 10 days,
            signerList: signerList,
            proposalExpirationPeriod: 15 days
        });
    }

    function test_ShouldEncodeInstallationParameters_1() public view {
        // 1
        bytes memory output = pluginSetup.encodeInstallationParameters(multisigSettings);

        bytes memory expected =
            hex"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000d2f00000000000000000000000000a0279152cf631d6c493901f9b576d88e2847bfa1000000000000000000000000000000000000000000000000000000000013c680";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldEncodeInstallationParameters_2() public {
        // 2
        signers = new address[](2);
        signers[0] = alice;
        signers[1] = bob;
        signerList =
            SignerList(createProxyAndCall(signerListBase, abi.encodeCall(SignerList.initialize, (IDAO(dao), signers))));

        multisigSettings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 5 days,
            signerList: signerList,
            proposalExpirationPeriod: 33 days
        });

        bytes memory output = pluginSetup.encodeInstallationParameters(multisigSettings);
        bytes memory expected =
            hex"00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000006978000000000000000000000000003a6a84cd762d9707a21605b548aaab891562aab00000000000000000000000000000000000000000000000000000000002b8180";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldDecodeInstallationParameters_1() public view {
        // 1
        bytes memory installationParams = pluginSetup.encodeInstallationParameters(multisigSettings);

        // Decode
        (Multisig.MultisigSettings memory outSettings) = pluginSetup.decodeInstallationParameters(installationParams);

        assertEq(outSettings.onlyListed, true, "Should be true");
        assertEq(outSettings.minApprovals, 3, "Should be 3");
        assertEq(outSettings.destinationProposalDuration, 10 days, "Should be 10 days");
    }

    function test_ShouldDecodeInstallationParameters_2() public {
        // 2
        signers = new address[](2);
        signers[0] = alice;
        signers[1] = bob;
        signerList =
            SignerList(createProxyAndCall(signerListBase, abi.encodeCall(SignerList.initialize, (IDAO(dao), signers))));

        multisigSettings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            destinationProposalDuration: 5 days,
            signerList: signerList,
            proposalExpirationPeriod: 55 days
        });

        bytes memory installationParams = pluginSetup.encodeInstallationParameters(multisigSettings);

        // Decode
        (Multisig.MultisigSettings memory outSettings) = pluginSetup.decodeInstallationParameters(installationParams);

        assertEq(outSettings.onlyListed, false, "Should be false");
        assertEq(outSettings.minApprovals, 1, "Should be 1");
        assertEq(outSettings.destinationProposalDuration, 5 days, "Should be 5 days");
    }

    function test_PrepareInstallationReturnsTheProperPermissions() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParameters(multisigSettings);

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
        bytes memory installationParams = pluginSetup.encodeInstallationParameters(multisigSettings);

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
