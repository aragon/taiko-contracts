// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {Multisig} from "../src/Multisig.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {
    SignerList,
    UPDATE_SIGNER_LIST_PERMISSION_ID,
    UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID
} from "../src/SignerList.sol";
import {EncryptionRegistry} from "../src/EncryptionRegistry.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {createProxyAndCall} from "../src/helpers/proxy.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";
import {IPlugin} from "@aragon/osx/core/plugin/IPlugin.sol";
import {IMultisig} from "../src/interfaces/IMultisig.sol";

uint64 constant MULTISIG_PROPOSAL_EXPIRATION_PERIOD = 10 days;
uint32 constant DESTINATION_PROPOSAL_DURATION = 9 days;

contract MultisigTest is AragonTest {
    DaoBuilder builder;
    DAO dao;
    Multisig multisig;
    OptimisticTokenVotingPlugin optimisticPlugin;
    SignerList signerList;
    EncryptionRegistry encryptionRegistry;

    address immutable SIGNER_LIST_BASE = address(new SignerList());

    // Events/errors to be tested here (duplicate)
    error DaoUnauthorized(address dao, address where, address who, bytes32 permissionId);
    error InvalidAddresslistUpdate(address member);
    error InvalidActions(uint256 proposalId);

    event MultisigSettingsUpdated(
        bool onlyListed,
        uint16 indexed minApprovals,
        uint64 destinationProposalDuration,
        SignerList signerList,
        uint64 proposalExpirationPeriod
    );
    // Multisig and OptimisticTokenVotingPlugin's event
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        IDAO.Action[] actions,
        uint256 allowFailureMap
    );
    event Approved(uint256 indexed proposalId, address indexed approver);
    event Executed(uint256 indexed proposalId);
    event Upgraded(address indexed implementation);

    function setUp() public {
        vm.startPrank(alice);

        builder = new DaoBuilder();
        (dao, optimisticPlugin, multisig,,, signerList, encryptionRegistry,) = builder.withMultisigMember(alice)
            .withMultisigMember(bob).withMultisigMember(carol).withMultisigMember(david).withMinApprovals(3).withDuration(
            DESTINATION_PROPOSAL_DURATION
        ).build();
    }

    modifier givenANewlyDeployedContract() {
        _;
    }

    modifier givenCallingInitialize() {
        _;
    }

    function test_GivenCallingInitialize() external givenANewlyDeployedContract givenCallingInitialize {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            destinationProposalDuration: 4 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        // It should initialize the first time
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        // It should refuse to initialize again
        vm.expectRevert("Initializable: contract is already initialized");
        multisig.initialize(dao, settings);

        // It should set the DAO address

        assertEq((address(multisig.dao())), address(dao), "Incorrect dao");

        // It should set the minApprovals

        (, uint16 minApprovals,,,) = multisig.multisigSettings();
        assertEq(minApprovals, uint16(3), "Incorrect minApprovals");
        settings.minApprovals = 1;
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));
        (, minApprovals,,,) = multisig.multisigSettings();
        assertEq(minApprovals, uint16(1), "Incorrect minApprovals");

        // It should set onlyListed

        (bool onlyListed,,,,) = multisig.multisigSettings();
        assertEq(onlyListed, true, "Incorrect onlyListed");
        settings.onlyListed = false;
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));
        (onlyListed,,,,) = multisig.multisigSettings();
        assertEq(onlyListed, false, "Incorrect onlyListed");

        // It should set destinationProposalDuration

        (,, uint64 destinationProposalDuration,,) = multisig.multisigSettings();
        assertEq(destinationProposalDuration, 4 days, "Incorrect destinationProposalDuration");
        settings.destinationProposalDuration = 3 days;
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));
        (,, destinationProposalDuration,,) = multisig.multisigSettings();
        assertEq(destinationProposalDuration, 3 days, "Incorrect destinationProposalDuration");

        // It should set signerList

        (,,, Addresslist givenSignerList,) = multisig.multisigSettings();
        assertEq(address(givenSignerList), address(signerList), "Incorrect addresslistSource");
        (,,,,, signerList,,) = builder.build();
        settings.signerList = signerList;
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));
        (,,, signerList,) = multisig.multisigSettings();
        assertEq(address(signerList), address(settings.signerList), "Incorrect addresslistSource");

        // It should set proposalExpirationPeriod

        (,,,, uint64 expirationPeriod) = multisig.multisigSettings();
        assertEq(expirationPeriod, MULTISIG_PROPOSAL_EXPIRATION_PERIOD, "Incorrect expirationPeriod");
        settings.proposalExpirationPeriod = 3 days;
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));
        (,,,, expirationPeriod) = multisig.multisigSettings();
        assertEq(expirationPeriod, 3 days, "Incorrect expirationPeriod");

        // It should emit MultisigSettingsUpdated

        (,,,,, SignerList newSignerList,,) = builder.build();

        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 2,
            destinationProposalDuration: 4 days,
            signerList: newSignerList,
            proposalExpirationPeriod: 15 days
        });
        vm.expectEmit();
        emit MultisigSettingsUpdated(false, uint16(2), 4 days, newSignerList, 15 days);

        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));
    }

    function test_RevertWhen_MinApprovalsIsGreaterThanSignerListLengthOnInitialize()
        external
        givenANewlyDeployedContract
        givenCallingInitialize
    {
        // It should revert
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5,
            destinationProposalDuration: 10 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 4, 5));
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        // It should revert (with onlyListed false)
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 5,
            destinationProposalDuration: 10 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 4, 5));
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        // It should not revert otherwise

        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 4,
            destinationProposalDuration: 10 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 4,
            destinationProposalDuration: 10 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));
    }

    function test_RevertWhen_MinApprovalsIsZeroOnInitialize()
        external
        givenANewlyDeployedContract
        givenCallingInitialize
    {
        // It should revert
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 0,
            destinationProposalDuration: 10 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        // It should revert (with onlyListed false)
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 0,
            destinationProposalDuration: 10 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        // It should not revert otherwise

        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 4,
            destinationProposalDuration: 10 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 4,
            destinationProposalDuration: 10 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));
    }

    function test_RevertWhen_SignerListIsInvalidOnInitialize()
        external
        givenANewlyDeployedContract
        givenCallingInitialize
    {
        // It should revert
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            destinationProposalDuration: 10 days,
            signerList: SignerList(address(dao)),
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(Multisig.InvalidSignerList.selector, address(dao)));
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        // ko 2
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            destinationProposalDuration: 10 days,
            signerList: SignerList(address(builder)),
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert();
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        // ok
        (,,,,, SignerList newSignerList,,) = builder.build();
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            destinationProposalDuration: 10 days,
            signerList: newSignerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));
    }

    function test_WhenCallingUpgradeTo() external {
        // It should revert when called without the permission
        address initialImplementation = multisig.implementation();
        address _newImplementation = address(new Multisig());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(multisig),
                alice,
                multisig.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );
        multisig.upgradeTo(_newImplementation);
        assertEq(multisig.implementation(), initialImplementation);

        // It should work when called with the permission
        dao.grant(address(multisig), alice, multisig.UPGRADE_PLUGIN_PERMISSION_ID());
        multisig.upgradeTo(_newImplementation);
    }

    function test_WhenCallingUpgradeToAndCall() external {
        // It should revert when called without the permission
        address initialImplementation = multisig.implementation();
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        address _newImplementation = address(new Multisig());

        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            destinationProposalDuration: 3 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(multisig),
                alice,
                multisig.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );
        multisig.upgradeToAndCall(_newImplementation, abi.encodeCall(Multisig.updateMultisigSettings, (settings)));
        assertEq(multisig.implementation(), initialImplementation);

        // It should work when called with the permission
        dao.grant(address(multisig), alice, multisig.UPGRADE_PLUGIN_PERMISSION_ID());
        multisig.upgradeToAndCall(_newImplementation, abi.encodeCall(Multisig.updateMultisigSettings, (settings)));
    }

    function test_WhenCallingSupportsInterface() external view {
        // It does not support the empty interface
        bool supported = multisig.supportsInterface(0);
        assertEq(supported, false, "Should not support the empty interface");

        // It supports IERC165Upgradeable
        supported = multisig.supportsInterface(type(IERC165Upgradeable).interfaceId);
        assertEq(supported, true, "Should support IERC165Upgradeable");

        // It supports IPlugin
        supported = multisig.supportsInterface(type(IPlugin).interfaceId);
        assertEq(supported, true, "Should support IPlugin");

        // It supports IProposal
        supported = multisig.supportsInterface(type(IProposal).interfaceId);
        assertEq(supported, true, "Should support IProposal");

        // It supports IMultisig
        supported = multisig.supportsInterface(type(IMultisig).interfaceId);
        assertEq(supported, true, "Should support IMultisig");
    }

    modifier whenCallingUpdateSettings() {
        _;
    }

    function test_WhenCallingUpdateSettings() external whenCallingUpdateSettings {
        // It should set the minApprovals
        // It should set onlyListed
        // It should set signerList
        // It should set destinationProposalDuration
        // It should set proposalExpirationPeriod
        // It should emit MultisigSettingsUpdated

        bool givenOnlyListed;
        uint16 givenMinApprovals;
        uint64 givenDestinationProposalDuration;
        SignerList givenSignerList;
        uint64 givenProposalExpirationPeriod;
        dao.grant(address(multisig), address(alice), multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // 1
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 1 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 1, 1 days, signerList, MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        multisig.updateMultisigSettings(settings);

        (
            givenOnlyListed,
            givenMinApprovals,
            givenDestinationProposalDuration,
            givenSignerList,
            givenProposalExpirationPeriod
        ) = multisig.multisigSettings();
        assertEq(givenOnlyListed, true, "onlyListed should be true");
        assertEq(givenMinApprovals, 1, "Incorrect givenMinApprovals");
        assertEq(address(givenSignerList), address(signerList), "Incorrect givenSignerList");
        assertEq(
            givenProposalExpirationPeriod,
            MULTISIG_PROPOSAL_EXPIRATION_PERIOD,
            "Incorrect givenProposalExpirationPeriod"
        );

        // 2
        (,,,,, SignerList newSignerList,,) = builder.build();

        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2,
            destinationProposalDuration: 2 days,
            signerList: newSignerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 2, 2 days, newSignerList, MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1);
        multisig.updateMultisigSettings(settings);

        (
            givenOnlyListed,
            givenMinApprovals,
            givenDestinationProposalDuration,
            givenSignerList,
            givenProposalExpirationPeriod
        ) = multisig.multisigSettings();
        assertEq(givenOnlyListed, true, "onlyListed should be true");
        assertEq(givenMinApprovals, 2, "Incorrect givenMinApprovals");
        assertEq(address(givenSignerList), address(newSignerList), "Incorrect givenSignerList");
        assertEq(
            givenProposalExpirationPeriod,
            MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1,
            "Incorrect givenProposalExpirationPeriod"
        );

        // 3
        (,,,,, newSignerList,,) = builder.build();

        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 3,
            destinationProposalDuration: 3 days,
            signerList: newSignerList,
            proposalExpirationPeriod: 4 days
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 3, 3 days, newSignerList, 4 days);
        multisig.updateMultisigSettings(settings);

        (
            givenOnlyListed,
            givenMinApprovals,
            givenDestinationProposalDuration,
            givenSignerList,
            givenProposalExpirationPeriod
        ) = multisig.multisigSettings();
        assertEq(givenOnlyListed, false, "onlyListed should be false");
        assertEq(givenMinApprovals, 3, "Incorrect givenMinApprovals");
        assertEq(address(givenSignerList), address(newSignerList), "Incorrect givenSignerList");
        assertEq(givenProposalExpirationPeriod, 4 days, "Incorrect givenProposalExpirationPeriod");

        // 4
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 4,
            destinationProposalDuration: 4 days,
            signerList: signerList,
            proposalExpirationPeriod: 8 days
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 4, 4 days, signerList, 8 days);
        multisig.updateMultisigSettings(settings);

        (
            givenOnlyListed,
            givenMinApprovals,
            givenDestinationProposalDuration,
            givenSignerList,
            givenProposalExpirationPeriod
        ) = multisig.multisigSettings();
        assertEq(givenOnlyListed, false, "onlyListed should be true");
        assertEq(givenMinApprovals, 4, "Incorrect givenMinApprovals");
        assertEq(address(givenSignerList), address(signerList), "Incorrect givenSignerList");
        assertEq(givenProposalExpirationPeriod, 8 days, "Incorrect givenProposalExpirationPeriod");
    }

    function test_RevertGiven_CallerHasNoPermission() external whenCallingUpdateSettings {
        // It should revert
        (,,,,, SignerList newSignerList,,) = builder.build();

        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 2,
            destinationProposalDuration: 17 days,
            signerList: newSignerList,
            proposalExpirationPeriod: 3 days
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(multisig),
                alice,
                multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
            )
        );
        multisig.updateMultisigSettings(settings);

        // Nothing changed
        (
            bool onlyListed,
            uint16 minApprovals,
            uint64 currentDestinationProposalDuration,
            Addresslist currentSource,
            uint64 expiration
        ) = multisig.multisigSettings();
        assertEq(onlyListed, true);
        assertEq(minApprovals, 3);
        assertEq(currentDestinationProposalDuration, 9 days);
        assertEq(address(currentSource), address(signerList));
        assertEq(expiration, 10 days);

        // It otherwise it should just work
        // Retry with the permission
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 2, 17 days, newSignerList, 3 days);
        multisig.updateMultisigSettings(settings);
    }

    function test_RevertWhen_MinApprovalsIsGreaterThanSignerListLengthOnUpdateSettings()
        external
        whenCallingUpdateSettings
    {
        // It should revert
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5,
            destinationProposalDuration: 4 days, // More than 4
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 4, 5));
        multisig.updateMultisigSettings(settings);

        // It should revert (with onlyListed false)
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 5,
            destinationProposalDuration: 4 days, // More than 4
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 4, 5));
        multisig.updateMultisigSettings(settings);

        // It should not revert otherwise

        // More signers
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        address[] memory signers = new address[](1);
        signers[0] = randomWallet;
        signerList.addSigners(signers);

        multisig.updateMultisigSettings(settings);
    }

    function test_RevertWhen_MinApprovalsIsZeroOnUpdateSettings() external whenCallingUpdateSettings {
        // It should revert
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 0,
            destinationProposalDuration: 4 days, // More than 4
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        multisig.updateMultisigSettings(settings);

        // It should revert (with onlyListed false)
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 0,
            destinationProposalDuration: 4 days, // More than 4
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        multisig.updateMultisigSettings(settings);

        // It should not revert otherwise

        settings.minApprovals = 1;
        multisig.updateMultisigSettings(settings);

        settings.onlyListed = true;
        multisig.updateMultisigSettings(settings);
    }

    function test_RevertWhen_SignerListIsInvalidOnUpdateSettings() external whenCallingUpdateSettings {
        // It should revert
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // ko
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            destinationProposalDuration: 10 days,
            signerList: SignerList(address(dao)),
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(Multisig.InvalidSignerList.selector, address(dao)));
        multisig.updateMultisigSettings(settings);

        // ko 2
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            destinationProposalDuration: 10 days,
            signerList: SignerList(address(builder)),
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert();
        multisig.updateMultisigSettings(settings);

        // ok
        (,,,,, SignerList newSignerList,,) = builder.build();
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            destinationProposalDuration: 10 days,
            signerList: newSignerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        multisig.updateMultisigSettings(settings);
    }

    function testFuzz_PermissionedUpdateSettings(address randomAccount) public {
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        (bool onlyListed, uint16 minApprovals, uint64 destMinDuration, SignerList givenSignerList, uint64 expiration) =
            multisig.multisigSettings();
        assertEq(minApprovals, 3, "Should be 3");
        assertEq(onlyListed, true, "Should be true");
        assertEq(destMinDuration, 9 days, "Incorrect destMinDuration");
        assertEq(address(givenSignerList), address(signerList), "Incorrect addresslistSource");
        assertEq(expiration, 10 days, "Should be 10");

        // in
        (,,,,, SignerList newSignerList,,) = builder.build();
        Multisig.MultisigSettings memory newSettings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 2,
            destinationProposalDuration: 5 days,
            signerList: newSignerList,
            proposalExpirationPeriod: 4 days
        });
        multisig.updateMultisigSettings(newSettings);

        (onlyListed, minApprovals, destMinDuration, givenSignerList, expiration) = multisig.multisigSettings();
        assertEq(minApprovals, 2, "Should be 2");
        assertEq(onlyListed, false, "Should be false");
        assertEq(destMinDuration, 5 days, "Incorrect destMinDuration B");
        assertEq(address(givenSignerList), address(newSignerList), "Incorrect signerList");
        assertEq(expiration, 4 days, "Should be 4");

        // out
        newSettings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 6 days,
            signerList: signerList,
            proposalExpirationPeriod: 1 days
        });
        multisig.updateMultisigSettings(newSettings);
        (onlyListed, minApprovals, destMinDuration, givenSignerList, expiration) = multisig.multisigSettings();
        assertEq(minApprovals, 1, "Should be 1");
        assertEq(onlyListed, true, "Should be true");
        assertEq(destMinDuration, 6 days, "Incorrect destMinDuration B");
        assertEq(address(givenSignerList), address(signerList), "Incorrect signerList");
        assertEq(expiration, 1 days, "Should be 1");

        vm.roll(block.number + 1);

        // someone else
        if (randomAccount != alice && randomAccount != address(0)) {
            vm.startPrank(randomAccount);

            (,,,,, newSignerList,,) = builder.build();
            newSettings = Multisig.MultisigSettings({
                onlyListed: false,
                minApprovals: 4,
                destinationProposalDuration: 4 days,
                signerList: newSignerList,
                proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
            });

            vm.expectRevert(
                abi.encodeWithSelector(
                    DaoUnauthorized.selector,
                    address(dao),
                    address(multisig),
                    randomAccount,
                    multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
                )
            );
            multisig.updateMultisigSettings(newSettings);

            (onlyListed, minApprovals, destMinDuration, givenSignerList, expiration) = multisig.multisigSettings();
            assertEq(minApprovals, 1, "Should still be 1");
            assertEq(onlyListed, true, "Should still be true");
            assertEq(destMinDuration, 6 days, "Should still be 6 days");
            assertEq(address(givenSignerList), address(signerList), "Should still be signerList");
            assertEq(expiration, 1 days, "Should still be 1");
        }
    }

    modifier whenCallingCreateProposal() {
        _;
    }

    function test_WhenCallingCreateProposal() external whenCallingCreateProposal {
        uint256 pid;
        bool executed;
        uint16 approvals;
        Multisig.ProposalParameters memory parameters;
        bytes memory metadataURI;
        OptimisticTokenVotingPlugin destinationPlugin;
        IDAO.Action[] memory inputActions = new IDAO.Action[](0);
        IDAO.Action[] memory outputActions = new IDAO.Action[](0);

        // It increments the proposal counter
        // It creates and return unique proposal IDs
        // It emits the ProposalCreated event
        // It creates a proposal with the given values

        assertEq(multisig.proposalCount(), 0, "Should have no proposals");

        // 1
        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 0,
            creator: alice,
            metadata: "ipfs://",
            startDate: uint64(block.timestamp),
            endDate: uint64(block.timestamp) + DESTINATION_PROPOSAL_DURATION,
            actions: inputActions,
            allowFailureMap: 0
        });
        multisig.createProposal("ipfs://", inputActions, optimisticPlugin, false);
        assertEq(pid, 0, "Should be 0");
        assertEq(multisig.proposalCount(), 1, "Should have 1 proposal");

        (executed, approvals, parameters, metadataURI, outputActions, destinationPlugin) = multisig.getProposal(pid);
        assertEq(executed, false, "Should be false");
        assertEq(approvals, 0, "Should be 0");
        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(
            parameters.expirationDate, block.timestamp + MULTISIG_PROPOSAL_EXPIRATION_PERIOD, "Incorrect expirationDate"
        );
        assertEq(metadataURI, "ipfs://", "Incorrect metadataURI");
        assertEq(outputActions.length, 0, "Incorrect actions length");
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destinationPlugin");

        // 2
        vm.startPrank(bob);
        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 100);

        inputActions = new IDAO.Action[](1);
        inputActions[0].to = carol;
        inputActions[0].value = 1 ether;
        address[] memory addrs = new address[](1);
        inputActions[0].data = abi.encodeCall(SignerList.addSigners, (addrs));

        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 1,
            creator: bob,
            metadata: "ipfs://more",
            startDate: uint64(block.timestamp),
            endDate: uint64(block.timestamp) + DESTINATION_PROPOSAL_DURATION,
            actions: inputActions,
            allowFailureMap: 0
        });
        pid = multisig.createProposal("ipfs://more", inputActions, optimisticPlugin, true);

        assertEq(pid, 1, "Should be 1");
        assertEq(multisig.proposalCount(), 2, "Should have 2 proposals");

        (executed, approvals, parameters, metadataURI, outputActions, destinationPlugin) = multisig.getProposal(pid);
        assertEq(executed, false, "Should be false");
        assertEq(approvals, 1, "Should be 1");
        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(
            parameters.expirationDate, block.timestamp + MULTISIG_PROPOSAL_EXPIRATION_PERIOD, "Incorrect expirationDate"
        );
        assertEq(metadataURI, "ipfs://more", "Incorrect metadataURI");
        assertEq(outputActions.length, 1, "Incorrect actions length");
        assertEq(outputActions[0].to, carol, "Incorrect to");
        assertEq(outputActions[0].value, 1 ether, "Incorrect value");
        assertEq(outputActions[0].data, abi.encodeCall(SignerList.addSigners, (addrs)), "Incorrect data");
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destinationPlugin");

        // 3
        vm.startPrank(carol);
        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 100);

        OptimisticTokenVotingPlugin newOptimistic;
        (, newOptimistic, multisig,,,,,) = builder.withMinApprovals(2).build();

        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 0,
            creator: carol,
            metadata: "ipfs://1234",
            startDate: uint64(block.timestamp),
            endDate: uint64(block.timestamp) + DESTINATION_PROPOSAL_DURATION,
            actions: inputActions,
            allowFailureMap: 0
        });
        pid = multisig.createProposal("ipfs://1234", inputActions, newOptimistic, true);

        (,, parameters,,, destinationPlugin) = multisig.getProposal(pid);
        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(address(destinationPlugin), address(newOptimistic), "Incorrect destinationPlugin");
    }

    function test_GivenSettingsChangedOnTheSameBlock() external whenCallingCreateProposal {
        // It reverts

        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 3,
            destinationProposalDuration: 4 days,
            signerList: signerList,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        multisig =
            Multisig(createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings))));

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalCreationForbidden.selector, alice));
        multisig.createProposal("", actions, optimisticPlugin, false);

        // It does not revert otherwise

        // Next block
        vm.roll(block.number + 1);
        multisig.createProposal("", actions, optimisticPlugin, false);
    }

    function test_GivenOnlyListedIsFalse() external whenCallingCreateProposal {
        // It allows anyone to create

        builder = new DaoBuilder();
        (, optimisticPlugin, multisig,,,,,) = builder.withMultisigMember(alice).withoutOnlyListed().build();

        vm.startPrank(randomWallet);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        multisig.createProposal("", actions, optimisticPlugin, false);
    }

    modifier givenOnlyListedIsTrue() {
        _;
    }

    function test_GivenCreationCallerIsNotListedOrAppointed()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        // It reverts

        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 3));

        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalCreationForbidden.selector, randomWallet));
        multisig.createProposal("", actions, optimisticPlugin, false);

        // 2
        vm.startPrank(taikoBridge);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalCreationForbidden.selector, taikoBridge));
        multisig.createProposal("", actions, optimisticPlugin, false);

        // It reverts if listed before but not now

        vm.startPrank(alice);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        signerList.removeSigners(addrs);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalCreationForbidden.selector, alice));
        multisig.createProposal("", actions, optimisticPlugin, false);
    }

    function test_GivenCreationCallerIsAppointedByAFormerSigner()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        // It reverts

        encryptionRegistry.appointWallet(randomWallet);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 3));

        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        signerList.removeSigners(addrs);

        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalCreationForbidden.selector, randomWallet));
        multisig.createProposal("", actions, optimisticPlugin, false);

        // Undo
        vm.startPrank(alice);
        signerList.addSigners(addrs);

        vm.startPrank(randomWallet);
        multisig.createProposal("", actions, optimisticPlugin, false);
    }

    function test_GivenCreationCallerIsListedAndSelfAppointed()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        // It creates the proposal

        vm.startPrank(alice);
        multisig.createProposal("a", actions, optimisticPlugin, false);

        vm.startPrank(bob);
        multisig.createProposal("b", actions, optimisticPlugin, false);

        vm.startPrank(carol);
        multisig.createProposal("c", actions, optimisticPlugin, false);

        vm.startPrank(david);
        multisig.createProposal("d", actions, optimisticPlugin, false);
    }

    function test_GivenCreationCallerIsListedAppointingSomeoneElseNow()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        // It creates the proposal

        vm.startPrank(alice);
        encryptionRegistry.appointWallet(address(0x1234));
        multisig.createProposal("a", actions, optimisticPlugin, false);

        vm.startPrank(bob);
        encryptionRegistry.appointWallet(address(0x2345));
        multisig.createProposal("b", actions, optimisticPlugin, false);

        vm.startPrank(carol);
        encryptionRegistry.appointWallet(address(0x3456));
        multisig.createProposal("c", actions, optimisticPlugin, false);

        vm.startPrank(david);
        encryptionRegistry.appointWallet(address(0x4567));
        multisig.createProposal("d", actions, optimisticPlugin, false);
    }

    function test_GivenCreationCallerIsAppointedByACurrentSigner()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        // It creates the proposal

        vm.startPrank(alice);
        encryptionRegistry.appointWallet(address(0x1234));
        vm.startPrank(address(0x1234));
        multisig.createProposal("a", actions, optimisticPlugin, false);

        vm.startPrank(bob);
        encryptionRegistry.appointWallet(address(0x2345));
        vm.startPrank(address(0x2345));
        multisig.createProposal("b", actions, optimisticPlugin, false);

        vm.startPrank(carol);
        encryptionRegistry.appointWallet(address(0x3456));
        vm.startPrank(address(0x3456));
        multisig.createProposal("c", actions, optimisticPlugin, false);

        vm.startPrank(david);
        encryptionRegistry.appointWallet(address(0x4567));
        vm.startPrank(address(0x4567));
        multisig.createProposal("d", actions, optimisticPlugin, false);
    }

    function test_GivenApproveProposalIsTrue() external whenCallingCreateProposal {
        uint256 pid;
        uint256 approvals;
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        // It creates and calls approval in one go

        vm.startPrank(alice);
        pid = multisig.createProposal("a", actions, optimisticPlugin, true);
        (, approvals,,,,) = multisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");

        vm.startPrank(bob);
        pid = multisig.createProposal("b", actions, optimisticPlugin, true);
        (, approvals,,,,) = multisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");
    }

    function test_GivenApproveProposalIsFalse() external whenCallingCreateProposal {
        uint256 pid;
        uint256 approvals;
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        // It only creates the proposal

        vm.startPrank(carol);
        pid = multisig.createProposal("c", actions, optimisticPlugin, false);
        (, approvals,,,,) = multisig.getProposal(pid);
        assertEq(approvals, 0, "Should be 0");

        vm.startPrank(david);
        pid = multisig.createProposal("d", actions, optimisticPlugin, false);
        (, approvals,,,,) = multisig.getProposal(pid);
        assertEq(approvals, 0, "Should be 0");
    }

    modifier givenTheProposalIsNotCreated() {
        // Alice: listed and self appointed

        // Bob: listed, appointing someone else now
        vm.startPrank(bob);
        encryptionRegistry.appointWallet(randomWallet);

        // Random Wallet: appointed by a listed signer

        // 0x1234: unlisted and unappointed

        _;
    }

    function test_WhenCallingGetProposalBeingUncreated() external givenTheProposalIsNotCreated {
        // It should return empty values

        bool executed;
        uint16 approvals;
        Multisig.ProposalParameters memory parameters;
        bytes memory metadataURI;
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        OptimisticTokenVotingPlugin destinationPlugin;

        (executed, approvals, parameters, metadataURI, actions, destinationPlugin) = multisig.getProposal(1234);

        assertEq(executed, false, "Should be false");
        assertEq(approvals, 0, "Should be 0");
        assertEq(parameters.minApprovals, 0, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, 0, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, 0, "Incorrect expirationDate");
        assertEq(metadataURI, "", "Incorrect metadataURI");
        assertEq(actions.length, 0, "Incorrect actions.length");
        assertEq(address(destinationPlugin), address(0), "Incorrect destinationPlugin");
    }

    function test_WhenCallingCanApproveAndApproveBeingUncreated() external givenTheProposalIsNotCreated {
        uint256 randomProposalId = 1234;
        bool canApprove;

        // It canApprove should return false (when listed and self appointed)
        vm.startPrank(alice);
        canApprove = multisig.canApprove(randomProposalId, alice);
        assertEq(canApprove, false, "Should be false");

        // It approve should revert (when listed and self appointed)
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, alice));
        multisig.approve(randomProposalId, true);

        // It canApprove should return false (when listed, appointing someone else now)
        randomProposalId++;
        vm.startPrank(bob);
        canApprove = multisig.canApprove(randomProposalId, bob);
        assertEq(canApprove, false, "Should be false");

        // It approve should revert (when listed, appointing someone else now)
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, bob));
        multisig.approve(randomProposalId, true);

        // It canApprove should return false (when appointed by a listed signer)
        randomProposalId++;
        vm.startPrank(randomWallet);
        canApprove = multisig.canApprove(randomProposalId, randomWallet);
        assertEq(canApprove, false, "Should be false");

        // It approve should revert (when appointed by a listed signer)
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, randomWallet));
        multisig.approve(randomProposalId, false);

        // It canApprove should return false (when unlisted and unappointed)
        randomProposalId++;
        vm.startPrank(address(1234));
        canApprove = multisig.canApprove(randomProposalId, address(1234));
        assertEq(canApprove, false, "Should be false");

        // It approve should revert (when unlisted and unappointed)
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, address(1234))
        );
        multisig.approve(randomProposalId, false);
    }

    function test_WhenCallingHasApprovedBeingUncreated() external givenTheProposalIsNotCreated {
        bool hasApproved;
        uint256 randomProposalId = 1234;
        // It hasApproved should always return false

        hasApproved = multisig.hasApproved(randomProposalId, alice);
        assertEq(hasApproved, false, "Should be false");

        randomProposalId++;
        hasApproved = multisig.hasApproved(randomProposalId, bob);
        assertEq(hasApproved, false, "Should be false");

        randomProposalId++;
        hasApproved = multisig.hasApproved(randomProposalId, randomWallet);
        assertEq(hasApproved, false, "Should be false");

        randomProposalId++;
        hasApproved = multisig.hasApproved(randomProposalId, address(1234));
        assertEq(hasApproved, false, "Should be false");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingUncreated() external givenTheProposalIsNotCreated {
        bool canExecute;
        uint256 randomProposalId = 1234;

        // It canExecute should return false (when listed and self appointed)
        vm.startPrank(alice);
        canExecute = multisig.canExecute(randomProposalId);
        assertEq(canExecute, false, "Should be false");

        // It execute should revert (when listed and self appointed)
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, randomProposalId));
        multisig.execute(randomProposalId);

        // It canExecute should return false (when listed, appointing someone else now)
        randomProposalId++;
        vm.startPrank(bob);
        canExecute = multisig.canExecute(randomProposalId);
        assertEq(canExecute, false, "Should be false");

        // It execute should revert (when listed, appointing someone else now)
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, randomProposalId));
        multisig.execute(randomProposalId);

        // It canExecute should return false (when appointed by a listed signer)
        randomProposalId++;
        vm.startPrank(randomWallet);
        canExecute = multisig.canExecute(randomProposalId);
        assertEq(canExecute, false, "Should be false");

        // It execute should revert (when appointed by a listed signer)
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, randomProposalId));
        multisig.execute(randomProposalId);

        // It canExecute should return false (when unlisted and unappointed)
        randomProposalId++;
        vm.startPrank(address(1234));
        canExecute = multisig.canExecute(randomProposalId);
        assertEq(canExecute, false, "Should be false");

        // It execute should revert (when unlisted and unappointed)
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, randomProposalId));
        multisig.execute(randomProposalId);
    }

    modifier givenTheProposalIsOpen() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 1));

        // Alice: listed on creation and self appointed

        // Bob: listed on creation, appointing someone else now
        vm.startPrank(bob);
        encryptionRegistry.appointWallet(randomWallet);

        // Random Wallet: appointed by a listed signer on creation
        // 0x1234: unlisted and unappointed on creation

        vm.deal(address(dao), 1 ether);

        // Create proposal 0
        IDAO.Action[] memory actions = new IDAO.Action[](2);
        actions[0].value = 0.25 ether;
        actions[0].to = address(alice);
        actions[0].data = hex"";
        actions[1].value = 0.75 ether;
        actions[1].to = address(dao);
        actions[1].data = abi.encodeCall(DAO.setMetadata, "ipfs://new-metadata");
        multisig.createProposal("ipfs://pub-metadata", actions, optimisticPlugin, false);

        // Remove (later)
        vm.roll(block.number + 50);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;
        vm.startPrank(alice);
        signerList.removeSigners(addrs);

        _;
    }

    function testFuzz_CanApproveReturnsfFalseIfNotCreated(uint256 randomProposalId) public view {
        // returns `false` if the proposal doesn't exist

        assertEq(multisig.canApprove(randomProposalId, alice), false, "Should be false");
        assertEq(multisig.canApprove(randomProposalId, bob), false, "Should be false");
        assertEq(multisig.canApprove(randomProposalId, carol), false, "Should be false");
        assertEq(multisig.canApprove(randomProposalId, david), false, "Should be false");
    }

    function testFuzz_ApproveRevertsIfNotCreated(uint256 randomProposalId) public {
        // Reverts if the proposal doesn't exist

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, alice));
        multisig.approve(randomProposalId, false);

        // 2
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, bob));
        multisig.approve(randomProposalId, false);

        // 3
        vm.startPrank(carol);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, carol));
        multisig.approve(randomProposalId, true);

        // 4
        vm.startPrank(david);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, david));
        multisig.approve(randomProposalId, true);
    }

    function testFuzz_CanExecuteReturnsFalseIfNotCreated(uint256 randomProposalId) public view {
        // returns `false` if the proposal doesn't exist

        assertEq(multisig.canExecute(randomProposalId), false, "Should be false");
    }

    function testFuzz_ExecuteRevertsIfNotCreated(uint256 randomProposalId) public {
        // reverts if the proposal doesn't exist

        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, randomProposalId));
        multisig.execute(randomProposalId);
    }

    function test_WhenCallingGetProposalBeingOpen() external givenTheProposalIsOpen {
        // It should return the right values

        (
            bool executed,
            uint16 approvals,
            Multisig.ProposalParameters memory parameters,
            bytes memory metadataURI,
            IDAO.Action[] memory proposalActions,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = multisig.getProposal(0);

        // Check basic proposal state
        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 0, "Should have no approvals");

        // Check parameters
        assertEq(parameters.minApprovals, 3, "Should require 3 approvals");
        assertEq(parameters.snapshotBlock, block.number - 1 - 50, "Incorrect snapshot block");
        assertEq(
            parameters.expirationDate,
            block.timestamp + MULTISIG_PROPOSAL_EXPIRATION_PERIOD,
            "Incorrect expiration date"
        );

        // Check metadata and plugin
        assertEq(metadataURI, "ipfs://pub-metadata", "Incorrect metadata URI");
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destination plugin");

        // Verify actions
        IDAO.Action[] memory actions = new IDAO.Action[](2);
        actions[0].value = 0.25 ether;
        actions[0].to = address(alice);
        actions[0].data = hex"";
        actions[1].value = 0.75 ether;
        actions[1].to = address(dao);
        actions[1].data = abi.encodeCall(DAO.setMetadata, "ipfs://new-metadata");

        assertEq(proposalActions.length, actions.length, "Actions length should match");
        for (uint256 i = 0; i < actions.length; i++) {
            assertEq(proposalActions[i].to, actions[i].to, "Action to should match");
            assertEq(proposalActions[i].value, actions[i].value, "Action value should match");
            assertEq(proposalActions[i].data, actions[i].data, "Action data should match");
        }
    }

    function test_WhenCallingCanApproveAndApproveBeingOpen() external givenTheProposalIsOpen {
        // It canApprove should return true (when listed on creation, self appointed now)
        // It approve should work (when listed on creation, self appointed now)
        // It approve should emit an event (when listed on creation, self appointed now)
        assertEq(multisig.canApprove(0, alice), true, "Alice should be able to approve");
        vm.expectEmit();
        emit Approved(0, alice);
        multisig.approve(0, false);
        assertEq(multisig.hasApproved(0, alice), true, "Alice's approval should be recorded");

        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It approve should revert (when listed on creation, appointing someone else now)
        assertEq(multisig.canApprove(0, bob), false, "Bob should be able to approve");
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, bob));
        multisig.approve(0, false);
        assertEq(multisig.hasApproved(0, bob), false, "Bob's approval should not be recorded");

        // It canApprove should return true (when currently appointed by a signer listed on creation)
        // It approve should work (when currently appointed by a signer listed on creation)
        // It approve should emit an event (when currently appointed by a signer listed on creation)
        assertEq(multisig.canApprove(0, randomWallet), true, "RandomWallet should be able to approve");
        vm.startPrank(randomWallet);
        vm.expectEmit();
        emit Approved(0, randomWallet);
        multisig.approve(0, false);
        assertEq(multisig.hasApproved(0, randomWallet), true, "RandomWallet's approval should be recorded");

        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when unlisted on creation, unappointed now)
        assertEq(multisig.canApprove(0, address(0x5555)), false, "Random wallet should not be able to approve");
        vm.startPrank(address(0x5555));
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, address(0x5555)));
        multisig.approve(0, false);

        // Check approval count
        (, uint16 approvals,,,,) = multisig.getProposal(0);
        assertEq(approvals, 2, "Should have 2 approvals total");

        // Test tryExecution parameter
        vm.startPrank(randomWallet);
        // Should not be able to approve again even with tryExecution
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, randomWallet));
        multisig.approve(0, true);

        // Carol
        vm.startPrank(carol);
        assertEq(multisig.canApprove(0, carol), true, "Carol should be able to approve");
        multisig.approve(0, false);

        // Should approve, pass but not execute (yet)
        bool executed;
        (executed, approvals,,,,) = multisig.getProposal(0);
        assertEq(executed, false, "Should not have executed");
        assertEq(approvals, 3, "Should have 3 approvals total");

        // David should approve and trigger auto execution
        vm.startPrank(david);
        assertEq(multisig.canApprove(0, david), true, "David should be able to approve");
        multisig.approve(0, true);

        (executed, approvals,,,,) = multisig.getProposal(0);
        assertEq(executed, true, "Should have executed");
        assertEq(approvals, 4, "Should have 4 approvals total");
    }

    function testFuzz_CanApproveReturnsfFalseIfNotListed(address randomWallet) public {
        // returns `false` if the approver is not listed

        {
            // Deploy a new multisig instance (more efficient than the builder for fuzz testing)
            Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
                onlyListed: true,
                minApprovals: 1,
                destinationProposalDuration: 4 days,
                signerList: signerList,
                proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
            });
            address[] memory signers = new address[](1);
            signers[0] = alice;

            multisig = Multisig(
                createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, settings)))
            );
            vm.roll(block.number + 1);
        }

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // ko
        if (randomWallet != alice && randomWallet != bob && randomWallet != carol && randomWallet != david) {
            assertEq(multisig.canApprove(pid, randomWallet), false, "Should be false");
        }

        // static ok
        assertEq(multisig.canApprove(pid, alice), true, "Should be true");
    }

    function testFuzz_ApproveRevertsIfNotListed(address randomSigner) public {
        // Reverts if the signer is not listed

        builder = new DaoBuilder();
        (,, multisig,,,,,) = builder.withMultisigMember(alice).withMinApprovals(1).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        if (randomSigner == alice) {
            return;
        }

        vm.startPrank(randomSigner);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, randomSigner));
        multisig.approve(pid, false);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, randomSigner));
        multisig.approve(pid, true);
    }

    function test_WhenCallingHasApprovedBeingOpen() external givenTheProposalIsOpen {
        // It hasApproved should return false until approved

        assertEq(multisig.hasApproved(0, alice), false, "Alice should not have approved");
        assertEq(multisig.hasApproved(0, bob), false, "Bob should not have approved");
        assertEq(multisig.hasApproved(0, carol), false, "Carol should not have approved");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingOpen() external givenTheProposalIsOpen {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)

        // vm.startPrank(alice);
        assertEq(multisig.canExecute(0), false, "Should not be executable with only 1 approval");
        vm.startPrank(bob);
        assertEq(multisig.canExecute(0), false, "Should not be executable with only 1 approval");
        vm.startPrank(randomWallet);
        assertEq(multisig.canExecute(0), false, "Should not be executable with only 1 approval");
        vm.startPrank(address(0x5555));
        assertEq(multisig.canExecute(0), false, "Should not be executable with only 1 approval");

        // It execute should revert (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It execute should revert (when unlisted on creation, unappointed now)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);
        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);
        vm.startPrank(address(0x5555));
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);

        // More approvals
        vm.startPrank(randomWallet);
        multisig.approve(0, false);

        assertEq(multisig.canExecute(0), false, "Should not be executable with only 2 approvals");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);

        // Add final approval
        vm.startPrank(carol);
        multisig.approve(0, false);

        assertEq(multisig.canExecute(0), true, "Should be executable with 3 approvals");
        multisig.execute(0);

        // Verify execution
        (bool executed,,,,,) = multisig.getProposal(0);
        assertEq(executed, true, "Should now be executed");
    }

    modifier givenTheProposalWasApprovedByTheAddress() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 1));

        // Alice: listed on creation and self appointed

        // Bob: listed on creation, appointing someone else now
        vm.startPrank(bob);
        encryptionRegistry.appointWallet(randomWallet);

        // Random Wallet: appointed by a listed signer on creation
        // 0x1234: unlisted and unappointed on creation

        vm.deal(address(dao), 1 ether);

        // Create proposal 0
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0.3 ether;
        actions[0].to = address(carol);
        actions[0].data = hex"";
        uint256 pid = multisig.createProposal("ipfs://more-metadata", actions, optimisticPlugin, false);

        // Remove (later)
        vm.roll(block.number + 50);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;
        vm.startPrank(alice);
        signerList.removeSigners(addrs);

        // Alice approves
        multisig.approve(pid, false);

        _;
    }

    function test_WhenCallingGetProposalBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It should return the right values

        (
            bool executed,
            uint16 approvals,
            Multisig.ProposalParameters memory parameters,
            bytes memory metadataURI,
            IDAO.Action[] memory proposalActions,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = multisig.getProposal(0);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 1, "Should have 1 approval");
        assertEq(parameters.minApprovals, 3, "Should require 3 approvals");
        assertEq(parameters.snapshotBlock, block.number - 1 - 50, "Incorrect snapshot block"); // -51 due to vm.roll(block.number + 50)
        assertEq(
            parameters.expirationDate, block.timestamp + MULTISIG_PROPOSAL_EXPIRATION_PERIOD, "Incorrect expiration"
        );
        assertEq(metadataURI, "ipfs://more-metadata", "Incorrect metadata URI");
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destination plugin");

        // Verify actions
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0.3 ether;
        actions[0].to = address(carol);
        actions[0].data = hex"";

        assertEq(proposalActions.length, actions.length, "Actions length should match");
        for (uint256 i = 0; i < actions.length; i++) {
            assertEq(proposalActions[i].to, actions[i].to, "Action to should match");
            assertEq(proposalActions[i].value, actions[i].value, "Action value should match");
            assertEq(proposalActions[i].data, actions[i].data, "Action data should match");
        }
    }

    function test_WhenCallingCanApproveAndApproveBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // Approve without executing
        vm.startPrank(randomWallet);
        multisig.approve(0, false);

        // It canApprove should return false (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)

        // It approve should revert (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It approve should revert (when unlisted on creation, unappointed now)

        // When listed on creation, self appointed now
        assertEq(multisig.canApprove(0, alice), false, "Alice should not be able to approve");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, alice));
        multisig.approve(0, false);

        // When listed on creation, appointing someone else now
        assertEq(multisig.canApprove(0, bob), false, "Bob should not be able to approve");
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, bob));
        multisig.approve(0, false);

        // When currently appointed by a signer listed on creation
        // RandomWallet should not be able to approve again
        assertEq(multisig.canApprove(0, randomWallet), false, "Random wallet should not be able to approve again");
        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, randomWallet));
        multisig.approve(0, false);

        // When unlisted on creation, unappointed now
        assertEq(multisig.canApprove(0, address(0x1234)), false, "Unlisted address should not be able to approve");
        vm.startPrank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, address(0x1234)));
        multisig.approve(0, false);
    }

    function test_WhenCallingHasApprovedBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It hasApproved should return false until approved

        assertEq(multisig.hasApproved(0, alice), true, "Alice should have approved");
        assertEq(multisig.hasApproved(0, bob), false, "Bob should not have approved");
        assertEq(multisig.hasApproved(0, carol), false, "Carol should not have approved");
        assertEq(multisig.hasApproved(0, david), false, "David should not have approved");
        assertEq(multisig.hasApproved(0, randomWallet), false, "Random wallet should not have approved");

        vm.startPrank(randomWallet); // Appointed
        multisig.approve(0, false);
        assertEq(multisig.hasApproved(0, bob), true, "Bob should have approved");

        vm.startPrank(carol);
        multisig.approve(0, false);
        assertEq(multisig.hasApproved(0, carol), true, "Carol should have approved");

        vm.startPrank(david);
        multisig.approve(0, false);
        assertEq(multisig.hasApproved(0, david), true, "Bob should have approved");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It execute should revert (when listed on creation, self appointed now)
        // It execute should revert (when currently appointed by a signer listed on creation)

        // It canExecute should return false (when listed on creation, self appointed now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)

        // It canExecute should return false with insufficient approvals
        // vm.startPrank(alice);
        assertEq(multisig.canExecute(0), false, "Should not be executable with only 1 approval");
        vm.startPrank(randomWallet);
        assertEq(multisig.canExecute(0), false, "Should not be executable with only 1 approval");

        // It execute should revert with insufficient approvals
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);
        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);

        // Add remaining approvals
        vm.startPrank(randomWallet);
        multisig.approve(0, false);

        // It canExecute should return false with insufficient approvals
        assertEq(multisig.canExecute(0), false, "Should not be executable with 2 approvals");

        vm.startPrank(carol);
        multisig.approve(0, false);

        // It canExecute should return true with sufficient approvals
        assertEq(multisig.canExecute(0), true, "Should be executable with 3 approvals");

        // It execute should work with sufficient approvals
        vm.expectEmit();
        emit Executed(0);
        multisig.execute(0);

        // Verify execution
        (bool executed,,,,,) = multisig.getProposal(0);
        assertEq(executed, true, "Should be executed");
    }

    modifier givenTheProposalPassed() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 1));

        // Alice: listed on creation and self appointed

        // Bob: listed on creation, appointing someone else now
        vm.startPrank(bob);
        encryptionRegistry.appointWallet(randomWallet);

        // Random Wallet: appointed by a listed signer on creation
        // 0x1234: unlisted and unappointed on creation

        vm.deal(address(dao), 1 ether);

        // Create proposal 0
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0.65 ether;
        actions[0].to = address(david);
        actions[0].data = hex"";
        uint256 pid = multisig.createProposal("ipfs://proposal-metadata-here", actions, optimisticPlugin, false);

        // Remove (later)
        vm.roll(block.number + 50);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;
        vm.startPrank(alice);
        signerList.removeSigners(addrs);

        multisig.approve(pid, false);

        vm.startPrank(randomWallet);
        multisig.approve(pid, false);

        vm.startPrank(carol);
        multisig.approve(pid, false);

        vm.startPrank(alice);

        _;
    }

    function test_WhenCallingGetProposalBeingPassed() external givenTheProposalPassed {
        // It should return the right values
        (
            bool executed,
            uint16 approvals,
            Multisig.ProposalParameters memory parameters,
            bytes memory metadataURI,
            IDAO.Action[] memory proposalActions,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = multisig.getProposal(0);

        assertEq(executed, false, "Should not be executed yet");
        assertEq(approvals, 3, "Should have 3 approvals");
        assertEq(parameters.minApprovals, 3, "Should require 3 approvals");
        assertEq(parameters.snapshotBlock, block.number - 1 - 50, "Incorrect snapshot block"); // -51 due to vm.roll(block.number + 50)
        assertEq(
            parameters.expirationDate, block.timestamp + MULTISIG_PROPOSAL_EXPIRATION_PERIOD, "Incorrect expiration"
        );
        assertEq(metadataURI, "ipfs://proposal-metadata-here", "Incorrect metadata URI");
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destination plugin");

        // Verify actions
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0.65 ether;
        actions[0].to = address(david);
        actions[0].data = hex"";

        assertEq(proposalActions.length, actions.length, "Actions length should match");
        for (uint256 i = 0; i < actions.length; i++) {
            assertEq(proposalActions[i].to, actions[i].to, "Action to should match");
            assertEq(proposalActions[i].value, actions[i].value, "Action value should match");
            assertEq(proposalActions[i].data, actions[i].data, "Action data should match");
        }
    }

    function test_WhenCallingCanApproveAndApproveBeingPassed() external givenTheProposalPassed {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)

        // It approve should revert (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It approve should revert (when unlisted on creation, unappointed now)

        // When listed on creation, self appointed now
        assertEq(multisig.canApprove(0, alice), false, "Alice should not be able to approve");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, alice));
        multisig.approve(0, false);

        // When listed on creation, appointing someone else now
        assertEq(multisig.canApprove(0, bob), false, "Bob should not be able to approve");
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, bob));
        multisig.approve(0, false);

        // When currently appointed by a signer listed on creation
        assertEq(multisig.canApprove(0, randomWallet), false, "Random wallet should not be able to approve");
        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, randomWallet));
        multisig.approve(0, false);

        // When unlisted on creation, unappointed now
        assertEq(multisig.canApprove(0, address(0x1234)), false, "Unlisted address should not be able to approve");
        vm.startPrank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, address(0x1234)));
        multisig.approve(0, false);
    }

    function test_WhenCallingHasApprovedBeingPassed() external givenTheProposalPassed {
        // It hasApproved should return false until approved

        assertEq(multisig.hasApproved(0, alice), true, "Alice should show as approved");
        assertEq(multisig.hasApproved(0, bob), true, "Bob should show as approved");
        assertEq(multisig.hasApproved(0, carol), true, "Carol should show as approved");
        assertEq(multisig.hasApproved(0, david), false, "David should not show as approved");
        assertEq(multisig.hasApproved(0, randomWallet), false, "Random wallet should not show as approved");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingPassed() external givenTheProposalPassed {
        // It execute recreates the proposal on the destination plugin
        // It The parameters of the recreated proposal match those of the executed one
        // It The proposal duration on the destination plugin matches the multisig settings
        // It A ProposalCreated event is emitted on the destination plugin

        // It canExecute should return true, always
        // vm.startPrank(alice);
        assertEq(multisig.canExecute(0), true, "Should be executable");
        vm.startPrank(randomWallet);
        assertEq(multisig.canExecute(0), true, "Should be executable");
        vm.startPrank(carol);
        assertEq(multisig.canExecute(0), true, "Should be executable");
        vm.startPrank(address(0x5555));
        assertEq(multisig.canExecute(0), true, "Should be executable");

        // It execute should work, when called by anyone
        vm.expectEmit();
        emit Executed(0);

        // It execute should emit an event, when called by anyone
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0.65 ether;
        actions[0].to = address(david);
        actions[0].data = hex"";

        // It execute recreates the proposal on the destination plugin
        uint256 targetPid = (block.timestamp << 128) | ((block.timestamp + DESTINATION_PROPOSAL_DURATION) << 64);
        vm.expectEmit();
        emit ProposalCreated(
            targetPid,
            address(multisig),
            uint64(block.timestamp),
            uint64(block.timestamp + DESTINATION_PROPOSAL_DURATION),
            "ipfs://proposal-metadata-here",
            actions,
            0
        );

        multisig.execute(0);

        // Verify execution
        (bool executed,,,,,) = multisig.getProposal(0);
        assertEq(executed, true, "Should be executed");

        // Verify proposal recreation in destination plugin
        (
            bool open,
            bool destExecuted,
            ,
            uint256 vetoTally,
            bytes memory metadataUri,
            IDAO.Action[] memory destActions,
            uint256 allowFailureMap
        ) = optimisticPlugin.getProposal(targetPid);

        assertEq(open, true, "Destination proposal should be open");
        assertEq(destExecuted, false, "Destination proposal should not be executed");
        assertEq(vetoTally, 0, "Veto tally should be 0");
        assertEq(metadataUri, "ipfs://proposal-metadata-here", "Metadata URI should match");
        assertEq(destActions.length, actions.length, "Actions should match");
        assertEq(allowFailureMap, 0, "Allow failure map should be 0");
    }

    function test_GivenTaikoL1IsIncompatible() external givenTheProposalPassed {
        // Recreate with L1 incompatible
        (dao, optimisticPlugin, multisig,,, signerList, encryptionRegistry,) = builder.withIncompatibleTaikoL1().build();

        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 1));

        // Alice: listed on creation and self appointed
        // Bob: listed on creation, appointing someone else now
        vm.startPrank(bob);
        encryptionRegistry.appointWallet(randomWallet);
        // Random Wallet: appointed by a listed signer on creation
        // 0x1234: unlisted and unappointed on creation

        vm.deal(address(dao), 1 ether);

        // Create proposal 0
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0.65 ether;
        actions[0].to = address(david);
        actions[0].data = hex"";
        uint256 pid = multisig.createProposal("ipfs://proposal-metadata-here", actions, optimisticPlugin, false);

        vm.startPrank(alice);
        multisig.approve(pid, false);
        vm.startPrank(randomWallet);
        multisig.approve(pid, false);
        vm.startPrank(carol);
        multisig.approve(pid, false);

        vm.startPrank(alice);

        // It executes successfully, regardless
        vm.expectEmit();
        emit Executed(0);

        vm.expectEmit();
        emit ProposalCreated(
            ((uint256(block.timestamp) << 128) | (uint256(block.timestamp + DESTINATION_PROPOSAL_DURATION) << 64)),
            address(multisig),
            uint64(block.timestamp),
            uint64(block.timestamp + DESTINATION_PROPOSAL_DURATION),
            "ipfs://proposal-metadata-here",
            actions,
            0
        );

        multisig.execute(0);

        // Verify execution
        (bool executed,,,,,) = multisig.getProposal(0);
        assertEq(executed, true, "Should be executed");
    }

    modifier givenTheProposalIsAlreadyExecuted() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 1));

        // Alice: listed on creation and self appointed

        // Bob: listed on creation, appointing someone else now
        vm.startPrank(bob);
        encryptionRegistry.appointWallet(randomWallet);

        // Random Wallet: appointed by a listed signer on creation
        // 0x1234: unlisted and unappointed on creation

        vm.deal(address(dao), 1 ether);

        // Create proposal 0
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0;
        actions[0].to = address(bob);
        actions[0].data = hex"";
        uint256 pid = multisig.createProposal("ipfs://the-metadata-here", actions, optimisticPlugin, false);

        // Remove (later)
        vm.roll(block.number + 50);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;
        vm.startPrank(alice);
        signerList.removeSigners(addrs);

        multisig.approve(pid, false);

        vm.startPrank(randomWallet);
        multisig.approve(pid, false);

        vm.startPrank(carol);
        multisig.approve(pid, false);

        multisig.execute(pid);

        vm.startPrank(alice);

        _;
    }

    function test_WhenCallingGetProposalBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It should return the right values

        (
            bool executed,
            uint16 approvals,
            Multisig.ProposalParameters memory parameters,
            bytes memory metadataURI,
            IDAO.Action[] memory proposalActions,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = multisig.getProposal(0);

        assertEq(executed, true, "Should be executed");
        assertEq(approvals, 3, "Should have 3 approvals");
        assertEq(parameters.minApprovals, 3, "Should require 3 approvals");
        assertEq(parameters.snapshotBlock, block.number - 1 - 50, "Incorrect snapshot block"); // -51 due to vm.roll(block.number + 50)
        assertEq(
            parameters.expirationDate, block.timestamp + MULTISIG_PROPOSAL_EXPIRATION_PERIOD, "Incorrect expiration"
        );
        assertEq(metadataURI, "ipfs://the-metadata-here", "Incorrect metadata URI");
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destination plugin");

        // Verify actions
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0;
        actions[0].to = address(bob);
        actions[0].data = hex"";

        assertEq(proposalActions.length, actions.length, "Actions length should match");
        for (uint256 i = 0; i < actions.length; i++) {
            assertEq(proposalActions[i].to, actions[i].to, "Action to should match");
            assertEq(proposalActions[i].value, actions[i].value, "Action value should match");
            assertEq(proposalActions[i].data, actions[i].data, "Action data should match");
        }
    }

    function test_WhenCallingCanApproveAndApproveBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It approve should revert (when unlisted on creation, unappointed now)

        // When listed on creation, self appointed now
        assertEq(multisig.canApprove(0, alice), false, "Alice should not be able to approve");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, alice));
        multisig.approve(0, false);

        // When listed on creation, appointing someone else now
        assertEq(multisig.canApprove(0, bob), false, "Bob should not be able to approve");
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, bob));
        multisig.approve(0, false);

        // When currently appointed by a signer listed on creation
        assertEq(multisig.canApprove(0, randomWallet), false, "Random wallet should not be able to approve");
        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, randomWallet));
        multisig.approve(0, false);

        // When unlisted on creation, unappointed now
        assertEq(multisig.canApprove(0, address(0x1234)), false, "Unlisted address should not be able to approve");
        vm.startPrank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, address(0x1234)));
        multisig.approve(0, false);
    }

    function test_WhenCallingHasApprovedBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It hasApproved should return false until approved

        assertEq(multisig.hasApproved(0, alice), true, "Alice should show as approved");
        assertEq(multisig.hasApproved(0, bob), true, "Bob should show as approved");
        assertEq(multisig.hasApproved(0, carol), true, "Carol should show as approved");
        assertEq(multisig.hasApproved(0, david), false, "David should not show as approved");
        assertEq(multisig.hasApproved(0, randomWallet), false, "Random wallet should not show as approved");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It execute should revert (when unlisted on creation, unappointed now)

        // When listed on creation, self appointed now
        // vm.startPrank(alice);
        assertEq(multisig.canExecute(0), false, "Should not be executable after execution");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);

        // When listed on creation, appointing someone else now
        vm.startPrank(bob);
        assertEq(multisig.canExecute(0), false, "Should not be executable after execution");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);

        // When currently appointed by a signer listed on creation
        vm.startPrank(randomWallet);
        assertEq(multisig.canExecute(0), false, "Should not be executable after execution");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);

        // When unlisted on creation, unappointed now
        vm.startPrank(address(0x1234));
        assertEq(multisig.canExecute(0), false, "Should not be executable after execution");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);
    }

    modifier givenTheProposalExpired() {
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 1));

        // Alice: listed on creation and self appointed

        // Bob: listed on creation, appointing someone else now
        vm.startPrank(bob);
        encryptionRegistry.appointWallet(randomWallet);

        // Random Wallet: appointed by a listed signer on creation
        // 0x1234: unlisted and unappointed on creation

        vm.deal(address(dao), 1 ether);

        // Create proposal 0
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0;
        actions[0].to = address(bob);
        actions[0].data = hex"";
        uint256 pid = multisig.createProposal("ipfs://", actions, optimisticPlugin, false);

        // Remove (later)
        vm.roll(block.number + 50);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;
        vm.startPrank(alice);
        signerList.removeSigners(addrs);

        multisig.approve(pid, false);

        vm.startPrank(randomWallet);
        multisig.approve(pid, false);

        vm.warp(block.timestamp + MULTISIG_PROPOSAL_EXPIRATION_PERIOD);

        vm.startPrank(alice);

        _;
    }

    function test_WhenCallingGetProposalBeingExpired() external givenTheProposalExpired {
        // It should return the right values

        (
            bool executed,
            uint16 approvals,
            Multisig.ProposalParameters memory parameters,
            bytes memory metadataURI,
            IDAO.Action[] memory proposalActions,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = multisig.getProposal(0);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 2, "Should have 2 approvals");
        assertEq(parameters.minApprovals, 3, "Should require 3 approvals");
        assertEq(parameters.snapshotBlock, block.number - 1 - 50, "Incorrect snapshot block");
        assertEq(parameters.expirationDate, block.timestamp, "Should be expired");
        assertEq(metadataURI, "ipfs://", "Incorrect metadata URI");
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destination plugin");

        // Verify actions
        assertEq(proposalActions.length, 1, "Should have 1 action");
        assertEq(proposalActions[0].to, address(bob), "Incorrect action target");
        assertEq(proposalActions[0].value, 0, "Incorrect action value");
        assertEq(proposalActions[0].data, "", "Incorrect action data");
    }

    function test_WhenCallingCanApproveAndApproveBeingExpired() external givenTheProposalExpired {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It approve should revert (when unlisted on creation, unappointed now)

        // When listed on creation, self appointed now
        assertEq(multisig.canApprove(0, alice), false, "Alice should not be able to approve expired proposal");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, alice));
        multisig.approve(0, false);

        // When listed on creation, appointing someone else now
        assertEq(multisig.canApprove(0, bob), false, "Bob should not be able to approve expired proposal");
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, bob));
        multisig.approve(0, false);

        // When currently appointed by a signer listed on creation
        assertEq(
            multisig.canApprove(0, randomWallet), false, "Random wallet should not be able to approve expired proposal"
        );
        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, randomWallet));
        multisig.approve(0, false);

        // When unlisted on creation, unappointed now
        address unlistedAddress = address(0x1234);
        assertEq(
            multisig.canApprove(0, unlistedAddress),
            false,
            "Unlisted address should not be able to approve expired proposal"
        );
        vm.startPrank(unlistedAddress);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 0, unlistedAddress));
        multisig.approve(0, false);
    }

    function test_WhenCallingHasApprovedBeingExpired() external givenTheProposalExpired {
        // It hasApproved should return false until approved

        assertEq(multisig.hasApproved(0, alice), true, "Alice should show as approved");
        assertEq(multisig.hasApproved(0, bob), true, "Bob should show as approved");
        assertEq(multisig.hasApproved(0, carol), false, "Carol should not show as approved");
        assertEq(multisig.hasApproved(0, david), false, "David should not show as approved");
        assertEq(multisig.hasApproved(0, randomWallet), false, "Random wallet should not show as approved");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingExpired() external givenTheProposalExpired {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)
        // It execute should revert (when unlisted on creation, unappointed now)

        // When listed on creation, self appointed now
        assertEq(multisig.canExecute(0), false, "Should not be executable when expired");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);

        // When listed on creation, appointing someone else now
        vm.startPrank(bob);
        assertEq(multisig.canExecute(0), false, "Should not be executable when expired");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);

        // When currently appointed by a signer listed on creation
        vm.startPrank(randomWallet);
        assertEq(multisig.canExecute(0), false, "Should not be executable when expired");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);

        // When unlisted on creation, unappointed now
        vm.startPrank(address(0x1234));
        assertEq(multisig.canExecute(0), false, "Should not be executable when expired");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 0));
        multisig.execute(0);
    }
}
