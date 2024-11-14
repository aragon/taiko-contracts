// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {EmergencyMultisig} from "../src/EmergencyMultisig.sol";
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
import {IEmergencyMultisig} from "../src/interfaces/IEmergencyMultisig.sol";

uint64 constant EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD = 10 days;

contract EmergencyMultisigTest is AragonTest {
    DaoBuilder builder;
    DAO dao;
    EmergencyMultisig eMultisig;
    OptimisticTokenVotingPlugin optimisticPlugin;
    SignerList signerList;
    EncryptionRegistry encryptionRegistry;

    address immutable SIGNER_LIST_BASE = address(new SignerList());

    // Events/errors to be tested here (duplicate)
    error DaoUnauthorized(address dao, address where, address who, bytes32 permissionId);
    error InvalidAddresslistUpdate(address member);
    error InvalidActions(uint256 proposalId);

    event MultisigSettingsUpdated(
        bool onlyListed, uint16 indexed minApprovals, SignerList signerList, uint64 proposalExpirationPeriod
    );

    event EmergencyProposalCreated(uint256 indexed proposalId, address indexed creator, bytes encryptedPayloadURI);

    // OptimisticTokenVotingPlugin's event
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
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, optimisticPlugin,, eMultisig,, signerList, encryptionRegistry,) = builder.withMultisigMember(alice)
            .withMultisigMember(bob).withMultisigMember(carol).withMultisigMember(david).withMinApprovals(3).withMinDuration(
            0
        ).build();
    }

    modifier givenANewlyDeployedContract() {
        _;
    }

    modifier givenCallingInitialize() {
        _;
    }

    function test_GivenCallingInitialize() external givenANewlyDeployedContract givenCallingInitialize {
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        // It should initialize the first time
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // It should refuse to initialize again
        vm.expectRevert("Initializable: contract is already initialized");
        eMultisig.initialize(dao, settings);

        // It should set the DAO address

        assertEq((address(eMultisig.dao())), address(dao), "Incorrect dao");

        // It should set the minApprovals

        (, uint16 minApprovals,,) = eMultisig.multisigSettings();
        assertEq(minApprovals, uint16(3), "Incorrect minApprovals");
        settings.minApprovals = 1;
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
        (, minApprovals,,) = eMultisig.multisigSettings();
        assertEq(minApprovals, uint16(1), "Incorrect minApprovals");

        // It should set onlyListed

        (bool onlyListed,,,) = eMultisig.multisigSettings();
        assertEq(onlyListed, true, "Incorrect onlyListed");
        settings.onlyListed = false;
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
        (onlyListed,,,) = eMultisig.multisigSettings();
        assertEq(onlyListed, false, "Incorrect onlyListed");

        // It should set signerList

        (,, Addresslist givenSignerList,) = eMultisig.multisigSettings();
        assertEq(address(givenSignerList), address(signerList), "Incorrect addresslistSource");
        (,,,,, signerList,,) = builder.build();
        settings.signerList = signerList;
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
        (,, signerList,) = eMultisig.multisigSettings();
        assertEq(address(signerList), address(settings.signerList), "Incorrect addresslistSource");

        // It should set proposalExpirationPeriod

        (,,, uint64 expirationPeriod) = eMultisig.multisigSettings();
        assertEq(expirationPeriod, EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD, "Incorrect expirationPeriod");
        settings.proposalExpirationPeriod = 3 days;
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
        (,,, expirationPeriod) = eMultisig.multisigSettings();
        assertEq(expirationPeriod, 3 days, "Incorrect expirationPeriod");

        // It should emit MultisigSettingsUpdated

        (,,,,, SignerList newSignerList,,) = builder.build();

        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 2,
            signerList: newSignerList,
            proposalExpirationPeriod: 15 days
        });
        vm.expectEmit();
        emit MultisigSettingsUpdated(false, uint16(2), newSignerList, 15 days);

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    function test_RevertWhen_MinApprovalsIsGreaterThanSignerListLengthOnInitialize()
        external
        givenANewlyDeployedContract
        givenCallingInitialize
    {
        // It should revert
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 4, 5));
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // It should revert (with onlyListed false)
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 5,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 4, 5));
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // It should not revert otherwise

        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 4,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 4,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    function test_RevertWhen_MinApprovalsIsZeroOnInitialize()
        external
        givenANewlyDeployedContract
        givenCallingInitialize
    {
        // It should revert
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 0,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 1, 0));
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // It should revert (with onlyListed false)
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 0,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 1, 0));
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // It should not revert otherwise

        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 4,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 4,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    function test_RevertWhen_SignerListIsInvalidOnInitialize()
        external
        givenANewlyDeployedContract
        givenCallingInitialize
    {
        // It should revert
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            signerList: SignerList(address(dao)),
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.InvalidSignerList.selector, address(dao)));
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // ko 2
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            signerList: SignerList(address(builder)),
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert();
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // ok
        (,,,,, SignerList newSignerList,,) = builder.build();
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            signerList: newSignerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    function test_WhenCallingUpgradeTo() external {
        // It should revert when called without the permission
        address initialImplementation = eMultisig.implementation();
        address _newImplementation = address(new EmergencyMultisig());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(eMultisig),
                alice,
                eMultisig.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );
        eMultisig.upgradeTo(_newImplementation);
        assertEq(eMultisig.implementation(), initialImplementation);

        // It should work when called with the permission
        dao.grant(address(eMultisig), alice, eMultisig.UPGRADE_PLUGIN_PERMISSION_ID());
        eMultisig.upgradeTo(_newImplementation);
    }

    function test_WhenCallingUpgradeToAndCall() external {
        // It should revert when called without the permission
        address initialImplementation = eMultisig.implementation();
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        address _newImplementation = address(new EmergencyMultisig());

        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(eMultisig),
                alice,
                eMultisig.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );
        eMultisig.upgradeToAndCall(
            _newImplementation, abi.encodeCall(EmergencyMultisig.updateMultisigSettings, (settings))
        );
        assertEq(eMultisig.implementation(), initialImplementation);

        // It should work when called with the permission
        dao.grant(address(eMultisig), alice, eMultisig.UPGRADE_PLUGIN_PERMISSION_ID());
        eMultisig.upgradeToAndCall(
            _newImplementation, abi.encodeCall(EmergencyMultisig.updateMultisigSettings, (settings))
        );
    }

    function test_WhenCallingSupportsInterface() external view {
        // It does not support the empty interface
        bool supported = eMultisig.supportsInterface(0);
        assertEq(supported, false, "Should not support the empty interface");

        // It supports IERC165Upgradeable
        supported = eMultisig.supportsInterface(type(IERC165Upgradeable).interfaceId);
        assertEq(supported, true, "Should support IERC165Upgradeable");

        // It supports IPlugin
        supported = eMultisig.supportsInterface(type(IPlugin).interfaceId);
        assertEq(supported, true, "Should support IPlugin");

        // It supports IProposal
        supported = eMultisig.supportsInterface(type(IProposal).interfaceId);
        assertEq(supported, true, "Should support IProposal");

        // It supports IEmergencyMultisig
        supported = eMultisig.supportsInterface(type(IEmergencyMultisig).interfaceId);
        assertEq(supported, true, "Should support IEmergencyMultisig");
    }

    modifier whenCallingUpdateSettings() {
        _;
    }

    function test_WhenCallingUpdateSettings() external whenCallingUpdateSettings {
        // It should set the minApprovals
        // It should set onlyListed
        // It should set signerList
        // It should set proposalExpirationPeriod
        // It should emit MultisigSettingsUpdated

        bool givenOnlyListed;
        uint16 givenMinApprovals;
        SignerList givenSignerList;
        uint64 givenProposalExpirationPeriod;
        dao.grant(address(eMultisig), address(alice), eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // 1
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 1, signerList, EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        eMultisig.updateMultisigSettings(settings);

        (givenOnlyListed, givenMinApprovals, givenSignerList, givenProposalExpirationPeriod) =
            eMultisig.multisigSettings();
        assertEq(givenOnlyListed, true, "onlyListed should be true");
        assertEq(givenMinApprovals, 1, "Incorrect givenMinApprovals");
        assertEq(address(givenSignerList), address(signerList), "Incorrect givenSignerList");
        assertEq(
            givenProposalExpirationPeriod,
            EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD,
            "Incorrect givenProposalExpirationPeriod"
        );

        // 2
        (,,,,, SignerList newSignerList,,) = builder.build();

        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2,
            signerList: newSignerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 2, newSignerList, EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1);
        eMultisig.updateMultisigSettings(settings);

        (givenOnlyListed, givenMinApprovals, givenSignerList, givenProposalExpirationPeriod) =
            eMultisig.multisigSettings();
        assertEq(givenOnlyListed, true, "onlyListed should be true");
        assertEq(givenMinApprovals, 2, "Incorrect givenMinApprovals");
        assertEq(address(givenSignerList), address(newSignerList), "Incorrect givenSignerList");
        assertEq(
            givenProposalExpirationPeriod,
            EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1,
            "Incorrect givenProposalExpirationPeriod"
        );

        // 3
        (,,,,, newSignerList,,) = builder.build();

        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 3,
            signerList: newSignerList,
            proposalExpirationPeriod: 4 days
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 3, newSignerList, 4 days);
        eMultisig.updateMultisigSettings(settings);

        (givenOnlyListed, givenMinApprovals, givenSignerList, givenProposalExpirationPeriod) =
            eMultisig.multisigSettings();
        assertEq(givenOnlyListed, false, "onlyListed should be false");
        assertEq(givenMinApprovals, 3, "Incorrect givenMinApprovals");
        assertEq(address(givenSignerList), address(newSignerList), "Incorrect givenSignerList");
        assertEq(givenProposalExpirationPeriod, 4 days, "Incorrect givenProposalExpirationPeriod");

        // 4
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 4,
            signerList: signerList,
            proposalExpirationPeriod: 8 days
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 4, signerList, 8 days);
        eMultisig.updateMultisigSettings(settings);

        (givenOnlyListed, givenMinApprovals, givenSignerList, givenProposalExpirationPeriod) =
            eMultisig.multisigSettings();
        assertEq(givenOnlyListed, false, "onlyListed should be true");
        assertEq(givenMinApprovals, 4, "Incorrect givenMinApprovals");
        assertEq(address(givenSignerList), address(signerList), "Incorrect givenSignerList");
        assertEq(givenProposalExpirationPeriod, 8 days, "Incorrect givenProposalExpirationPeriod");
    }

    function test_RevertGiven_CallerHasNoPermission() external whenCallingUpdateSettings {
        // It should revert
        (,,,,, SignerList newSignerList,,) = builder.build();

        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 2,
            signerList: newSignerList,
            proposalExpirationPeriod: 3 days
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(eMultisig),
                alice,
                eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
            )
        );
        eMultisig.updateMultisigSettings(settings);

        // Nothing changed
        (bool onlyListed, uint16 minApprovals, Addresslist currentSource, uint64 expiration) =
            eMultisig.multisigSettings();
        assertEq(onlyListed, true);
        assertEq(minApprovals, 3);
        assertEq(address(currentSource), address(signerList));
        assertEq(expiration, 10 days);

        // It otherwise it should just work
        // Retry with the permission
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 2, newSignerList, 3 days);
        eMultisig.updateMultisigSettings(settings);
    }

    function test_RevertWhen_MinApprovalsIsGreaterThanSignerListLengthOnUpdateSettings()
        external
        whenCallingUpdateSettings
    {
        // It should revert
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 4, 5));
        eMultisig.updateMultisigSettings(settings);

        // It should revert (with onlyListed false)
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 5,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 4, 5));
        eMultisig.updateMultisigSettings(settings);

        // It should not revert otherwise

        // More signers
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        address[] memory signers = new address[](1);
        signers[0] = randomWallet;
        signerList.addSigners(signers);

        eMultisig.updateMultisigSettings(settings);
    }

    function test_RevertWhen_MinApprovalsIsZeroOnUpdateSettings() external whenCallingUpdateSettings {
        // It should revert
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 0,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 1, 0));
        eMultisig.updateMultisigSettings(settings);

        // It should revert (with onlyListed false)
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 0,
            signerList: signerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 1, 0));
        eMultisig.updateMultisigSettings(settings);

        // It should not revert otherwise

        settings.minApprovals = 1;
        eMultisig.updateMultisigSettings(settings);

        settings.onlyListed = true;
        eMultisig.updateMultisigSettings(settings);
    }

    function test_RevertWhen_SignerListIsInvalidOnUpdateSettings() external whenCallingUpdateSettings {
        // It should revert
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // ko
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            signerList: SignerList(address(dao)),
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.InvalidSignerList.selector, address(dao)));
        eMultisig.updateMultisigSettings(settings);

        // ko 2
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            signerList: SignerList(address(builder)),
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        vm.expectRevert();
        eMultisig.updateMultisigSettings(settings);

        // ok
        (,,,,, SignerList newSignerList,,) = builder.build();
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            signerList: newSignerList,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        eMultisig.updateMultisigSettings(settings);
    }

    function testFuzz_PermissionedUpdateSettings(address randomAccount) public {
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        (bool onlyListed, uint16 minApprovals, SignerList givenSignerList, uint64 expiration) =
            eMultisig.multisigSettings();
        assertEq(minApprovals, 3, "Should be 3");
        assertEq(onlyListed, true, "Should be true");
        assertEq(address(givenSignerList), address(signerList), "Incorrect addresslistSource");
        assertEq(expiration, 10 days, "Should be 10");

        // in
        (,,,,, SignerList newSignerList,,) = builder.build();
        EmergencyMultisig.MultisigSettings memory newSettings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 2,
            signerList: newSignerList,
            proposalExpirationPeriod: 4 days
        });
        eMultisig.updateMultisigSettings(newSettings);

        (onlyListed, minApprovals, givenSignerList, expiration) = eMultisig.multisigSettings();
        assertEq(minApprovals, 2, "Should be 2");
        assertEq(onlyListed, false, "Should be false");
        assertEq(address(givenSignerList), address(newSignerList), "Incorrect signerList");
        assertEq(expiration, 4 days, "Should be 4");

        // out
        newSettings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            signerList: signerList,
            proposalExpirationPeriod: 1 days
        });
        eMultisig.updateMultisigSettings(newSettings);
        (onlyListed, minApprovals, givenSignerList, expiration) = eMultisig.multisigSettings();
        assertEq(minApprovals, 1, "Should be 1");
        assertEq(onlyListed, true, "Should be true");
        assertEq(address(givenSignerList), address(signerList), "Incorrect signerList");
        assertEq(expiration, 1 days, "Should be 1");

        vm.roll(block.number + 1);

        // someone else
        if (randomAccount != alice && randomAccount != address(0)) {
            vm.startPrank(randomAccount);

            (,,,,, newSignerList,,) = builder.build();
            newSettings = EmergencyMultisig.MultisigSettings({
                onlyListed: false,
                minApprovals: 4,
                signerList: newSignerList,
                proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
            });

            vm.expectRevert(
                abi.encodeWithSelector(
                    DaoUnauthorized.selector,
                    address(dao),
                    address(eMultisig),
                    randomAccount,
                    eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
                )
            );
            eMultisig.updateMultisigSettings(newSettings);

            (onlyListed, minApprovals, givenSignerList, expiration) = eMultisig.multisigSettings();
            assertEq(minApprovals, 1, "Should still be 1");
            assertEq(onlyListed, true, "Should still be true");
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
        EmergencyMultisig.ProposalParameters memory parameters;
        bytes memory encryptedPayloadURI;
        bytes32 publicMetadataUriHash;
        bytes32 destinationActionsHash;
        OptimisticTokenVotingPlugin destinationPlugin;

        // It increments the proposal counter
        // It creates and return unique proposal IDs
        // It emits the EmergencyProposalCreated event
        // It creates a proposal with the given values

        assertEq(eMultisig.proposalCount(), 0, "Should have no proposals");

        // 1
        vm.expectEmit();
        emit EmergencyProposalCreated({proposalId: 0, creator: alice, encryptedPayloadURI: "ipfs://"});
        pid = eMultisig.createProposal(
            "ipfs://",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000123400000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            false
        );
        assertEq(pid, 0, "Should be 0");
        assertEq(eMultisig.proposalCount(), 1, "Should have 1 proposal");

        (
            executed,
            approvals,
            parameters,
            encryptedPayloadURI,
            publicMetadataUriHash,
            destinationActionsHash,
            destinationPlugin
        ) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should be false");
        assertEq(approvals, 0, "Should be 0");
        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(
            parameters.expirationDate,
            block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD,
            "Incorrect expirationDate"
        );
        assertEq(encryptedPayloadURI, "ipfs://", "Incorrect encryptedPayloadURI");
        assertEq(
            publicMetadataUriHash,
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            "Incorrect publicMetadataUriHash"
        );
        assertEq(
            destinationActionsHash,
            bytes32(0x0000123400000000000000000000000000000000000000000000000000000000),
            "Incorrect destinationActionsHash"
        );
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destinationPlugin");

        // 2
        vm.startPrank(bob);

        vm.expectEmit();
        emit EmergencyProposalCreated({proposalId: 1, creator: bob, encryptedPayloadURI: "ipfs://more"});
        pid = eMultisig.createProposal(
            "ipfs://more",
            bytes32(0x2345000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000234500000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            true
        );

        assertEq(pid, 1, "Should be 1");
        assertEq(eMultisig.proposalCount(), 2, "Should have 2 proposals");

        (
            executed,
            approvals,
            parameters,
            encryptedPayloadURI,
            publicMetadataUriHash,
            destinationActionsHash,
            destinationPlugin
        ) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should be false");
        assertEq(approvals, 1, "Should be 1");
        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(
            parameters.expirationDate,
            block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD,
            "Incorrect expirationDate"
        );
        assertEq(encryptedPayloadURI, "ipfs://more", "Incorrect encryptedPayloadURI");
        assertEq(
            publicMetadataUriHash,
            bytes32(0x2345000000000000000000000000000000000000000000000000000000000000),
            "Incorrect publicMetadataUriHash"
        );
        assertEq(
            destinationActionsHash,
            bytes32(0x0000234500000000000000000000000000000000000000000000000000000000),
            "Incorrect destinationActionsHash"
        );
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destinationPlugin");

        // 3
        vm.startPrank(carol);
        OptimisticTokenVotingPlugin newOptimistic;
        (, newOptimistic,, eMultisig,,,,) = builder.withMinApprovals(2).build();

        vm.expectEmit();
        emit EmergencyProposalCreated({proposalId: 0, creator: carol, encryptedPayloadURI: "ipfs://more"});
        pid = eMultisig.createProposal(
            "ipfs://more",
            bytes32(0x2345000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000234500000000000000000000000000000000000000000000000000000000),
            newOptimistic,
            true
        );

        (,, parameters,,,, destinationPlugin) = eMultisig.getProposal(pid);
        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(address(destinationPlugin), address(newOptimistic), "Incorrect destinationPlugin");
    }

    function test_GivenSettingsChangedOnTheSameBlock() external whenCallingCreateProposal {
        {
            EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
                onlyListed: true,
                minApprovals: 3,
                signerList: signerList,
                proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
            });

            eMultisig = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
        }

        // It reverts
        // Same block
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, alice));
        eMultisig.createProposal("", bytes32(0), bytes32(0), optimisticPlugin, false);

        // It does not revert otherwise
        // Next block
        vm.roll(block.number + 1);
        eMultisig.createProposal("", bytes32(0), bytes32(0), optimisticPlugin, false);
    }

    function test_GivenOnlyListedIsFalse() external whenCallingCreateProposal {
        // It allows anyone to create

        // Deploy a new instance with custom settings
        (dao, optimisticPlugin,, eMultisig,,,,) = builder.withoutOnlyListed().build();

        vm.startPrank(randomWallet);
        eMultisig.createProposal("", 0, 0, optimisticPlugin, false);

        vm.startPrank(address(0x1234));
        eMultisig.createProposal("", 0, 0, optimisticPlugin, false);

        vm.startPrank(address(0x22345));
        eMultisig.createProposal("", 0, 0, optimisticPlugin, false);
    }

    modifier givenOnlyListedIsTrue() {
        _;
    }

    function test_GivenCreationCallerIsNotListedOrAppointed()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It reverts

        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 3));

        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, randomWallet));
        eMultisig.createProposal("", 0, 0, optimisticPlugin, false);

        // 2
        vm.startPrank(taikoBridge);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, taikoBridge));
        eMultisig.createProposal("", 0, 0, optimisticPlugin, false);

        // It reverts if listed before but not now

        vm.startPrank(alice);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);

        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        signerList.removeSigners(addrs);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, alice));
        eMultisig.createProposal("", 0, 0, optimisticPlugin, false);
    }

    function test_GivenCreationCallerIsAppointedByAFormerSigner()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It reverts

        encryptionRegistry.appointWallet(randomWallet);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_PERMISSION_ID);
        dao.grant(address(signerList), alice, UPDATE_SIGNER_LIST_SETTINGS_PERMISSION_ID);
        signerList.updateSettings(SignerList.Settings(encryptionRegistry, 3));

        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        signerList.removeSigners(addrs);

        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, randomWallet));
        eMultisig.createProposal("", 0, 0, optimisticPlugin, false);

        // Undo
        vm.startPrank(alice);
        signerList.addSigners(addrs);

        vm.startPrank(randomWallet);
        eMultisig.createProposal("", 0, 0, optimisticPlugin, false);
    }

    function test_GivenCreationCallerIsListedAndSelfAppointed()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It creates the proposal

        vm.startPrank(alice);
        eMultisig.createProposal("a", 0, 0, optimisticPlugin, false);

        vm.startPrank(bob);
        eMultisig.createProposal("b", 0, 0, optimisticPlugin, false);

        vm.startPrank(carol);
        eMultisig.createProposal("c", 0, 0, optimisticPlugin, true);

        vm.startPrank(david);
        eMultisig.createProposal("d", 0, 0, optimisticPlugin, false);
    }

    function test_GivenCreationCallerIsListedAppointingSomeoneElseNow()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It creates the proposal

        vm.startPrank(alice);
        encryptionRegistry.appointWallet(address(0x1234));
        eMultisig.createProposal("a", 0, 0, optimisticPlugin, false);

        vm.startPrank(bob);
        encryptionRegistry.appointWallet(address(0x2345));
        eMultisig.createProposal("b", 0, 0, optimisticPlugin, false);

        vm.startPrank(carol);
        encryptionRegistry.appointWallet(address(0x3456));
        eMultisig.createProposal("c", 0, 0, optimisticPlugin, false);

        vm.startPrank(david);
        encryptionRegistry.appointWallet(address(0x4567));
        eMultisig.createProposal("d", 0, 0, optimisticPlugin, false);
    }

    function test_GivenCreationCallerIsAppointedByACurrentSigner()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It creates the proposal

        vm.startPrank(alice);
        encryptionRegistry.appointWallet(address(0x1234));
        vm.startPrank(address(0x1234));
        eMultisig.createProposal("a", 0, 0, optimisticPlugin, false);

        vm.startPrank(bob);
        encryptionRegistry.appointWallet(address(0x2345));
        vm.startPrank(address(0x2345));
        eMultisig.createProposal("b", 0, 0, optimisticPlugin, false);

        vm.startPrank(carol);
        encryptionRegistry.appointWallet(address(0x3456));
        vm.startPrank(address(0x3456));
        eMultisig.createProposal("c", 0, 0, optimisticPlugin, false);

        vm.startPrank(david);
        encryptionRegistry.appointWallet(address(0x4567));
        vm.startPrank(address(0x4567));
        eMultisig.createProposal("d", 0, 0, optimisticPlugin, false);
    }

    function test_GivenApproveProposalIsTrue() external whenCallingCreateProposal {
        uint256 pid;
        uint256 approvals;

        // It creates and calls approval in one go

        vm.startPrank(alice);
        pid = eMultisig.createProposal("a", 0, 0, optimisticPlugin, true);
        (, approvals,,,,,) = eMultisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");

        vm.startPrank(bob);
        pid = eMultisig.createProposal("b", 0, 0, optimisticPlugin, true);
        (, approvals,,,,,) = eMultisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");
    }

    function test_GivenApproveProposalIsFalse() external whenCallingCreateProposal {
        uint256 pid;
        uint256 approvals;

        // It only creates the proposal

        vm.startPrank(alice);
        pid = eMultisig.createProposal("a", 0, 0, optimisticPlugin, true);
        (, approvals,,,,,) = eMultisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");

        vm.startPrank(bob);
        pid = eMultisig.createProposal("b", 0, 0, optimisticPlugin, true);
        (, approvals,,,,,) = eMultisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");

        vm.startPrank(carol);
        pid = eMultisig.createProposal("c", 0, 0, optimisticPlugin, false);
        (, approvals,,,,,) = eMultisig.getProposal(pid);
        assertEq(approvals, 0, "Should be 0");

        vm.startPrank(david);
        pid = eMultisig.createProposal("d", 0, 0, optimisticPlugin, false);
        (, approvals,,,,,) = eMultisig.getProposal(pid);
        assertEq(approvals, 0, "Should be 0");
    }

    function test_WhenCallingHashActions() external view {
        bytes32 hashedActions;
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        // It returns the right result
        // It reacts to any of the values changing
        // It same input produces the same output

        hashedActions = eMultisig.hashActions(actions);
        assertEq(hashedActions, hex"569e75fc77c1a856f6daaf9e69d8a9566ca34aa47f9133711ce065a571af0cfd");

        actions = new IDAO.Action[](1);
        actions[0] = IDAO.Action(address(0), 0, bytes(string("")));
        hashedActions = eMultisig.hashActions(actions);
        assertEq(hashedActions, hex"7cde746dfbb8dfd7721b5995769f873e3ff50416302673a354990b553bb0e208");

        actions = new IDAO.Action[](1);
        actions[0] = IDAO.Action(bob, 1 ether, bytes(string("")));
        hashedActions = eMultisig.hashActions(actions);
        assertEq(hashedActions, hex"e212a57e4595f81151b46333ea31e2d5043b53bd562141e1efa1b2778cb3c208");

        actions = new IDAO.Action[](2);
        actions[0] = IDAO.Action(bob, 1 ether, bytes(string("")));
        actions[1] = IDAO.Action(carol, 2 ether, bytes(string("data")));
        hashedActions = eMultisig.hashActions(actions);
        assertEq(hashedActions, hex"4be399aee320511a56f584fae21b92c78f47bff143ec3965b7d911776d39bc7d");
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
        EmergencyMultisig.ProposalParameters memory parameters;
        bytes memory encryptedPayloadURI;
        bytes32 publicMetadataUriHash;
        bytes32 destinationActionsHash;
        OptimisticTokenVotingPlugin destinationPlugin;

        (
            executed,
            approvals,
            parameters,
            encryptedPayloadURI,
            publicMetadataUriHash,
            destinationActionsHash,
            destinationPlugin
        ) = eMultisig.getProposal(1234);

        assertEq(executed, false, "Should be false");
        assertEq(approvals, 0, "Should be 0");
        assertEq(parameters.minApprovals, 0, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, 0, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, 0, "Incorrect expirationDate");
        assertEq(encryptedPayloadURI, "", "Incorrect encryptedPayloadURI");
        assertEq(publicMetadataUriHash, bytes32(0), "Incorrect publicMetadataUriHash");
        assertEq(destinationActionsHash, bytes32(0), "Incorrect destinationActionsHash");
        assertEq(address(destinationPlugin), address(0), "Incorrect destinationPlugin");
    }

    function test_WhenCallingCanApproveAndApproveBeingUncreated() external givenTheProposalIsNotCreated {
        uint256 randomProposalId = 1234;
        bool canApprove;

        // It canApprove should return false (when currently listed and self appointed)
        vm.startPrank(alice);
        canApprove = eMultisig.canApprove(randomProposalId, alice);
        assertEq(canApprove, false, "Should be false");

        // It approve should revert (when currently listed and self appointed)
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, randomProposalId, alice)
        );
        eMultisig.approve(randomProposalId);

        // It canApprove should return false (when currently listed, appointing someone else now)
        randomProposalId++;
        vm.startPrank(bob);
        canApprove = eMultisig.canApprove(randomProposalId, bob);
        assertEq(canApprove, false, "Should be false");

        // It approve should revert (when currently listed, appointing someone else now)
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, randomProposalId, bob));
        eMultisig.approve(randomProposalId);

        // It canApprove should return false (when appointed by a listed signer)
        randomProposalId++;
        vm.startPrank(randomWallet);
        canApprove = eMultisig.canApprove(randomProposalId, randomWallet);
        assertEq(canApprove, false, "Should be false");

        // It approve should revert (when appointed by a listed signer)
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, randomProposalId, randomWallet)
        );
        eMultisig.approve(randomProposalId);

        // It canApprove should return false (when currently unlisted and unappointed)
        randomProposalId++;
        vm.startPrank(address(1234));
        canApprove = eMultisig.canApprove(randomProposalId, address(1234));
        assertEq(canApprove, false, "Should be false");

        // It approve should revert (when currently unlisted and unappointed)
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, randomProposalId, address(1234))
        );
        eMultisig.approve(randomProposalId);
    }

    function test_WhenCallingHasApprovedBeingUncreated() external givenTheProposalIsNotCreated {
        bool hasApproved;
        uint256 randomProposalId = 1234;
        // It hasApproved should always return false

        hasApproved = eMultisig.hasApproved(randomProposalId, alice);
        assertEq(hasApproved, false, "Should be false");

        randomProposalId++;
        hasApproved = eMultisig.hasApproved(randomProposalId, bob);
        assertEq(hasApproved, false, "Should be false");

        randomProposalId++;
        hasApproved = eMultisig.hasApproved(randomProposalId, randomWallet);
        assertEq(hasApproved, false, "Should be false");

        randomProposalId++;
        hasApproved = eMultisig.hasApproved(randomProposalId, address(0x5555));
        assertEq(hasApproved, false, "Should be false");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingUncreated() external givenTheProposalIsNotCreated {
        uint256 randomProposalId = 1234;
        // It canExecute should always return false

        bool canExecute = eMultisig.canExecute(randomProposalId);
        assertEq(canExecute, false, "Should be false");
    }

    function testFuzz_WhenCallingCanExecuteOrExecuteBeingUncreated(uint256 randomProposalId)
        external
        givenTheProposalIsNotCreated
    {
        // It canExecute should always return false

        bool canExecute = eMultisig.canExecute(randomProposalId);
        assertEq(canExecute, false, "Should be false");
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

        // Create proposal
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"";
        bytes32 metadataUriHash = keccak256("ipfs://the-metadata");
        bytes32 actionsHash = eMultisig.hashActions(actions);
        eMultisig.createProposal("ipfs://encrypted", metadataUriHash, actionsHash, optimisticPlugin, false);

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

        assertEq(eMultisig.canApprove(randomProposalId, alice), false, "Should be false");
        assertEq(eMultisig.canApprove(randomProposalId, bob), false, "Should be false");
        assertEq(eMultisig.canApprove(randomProposalId, carol), false, "Should be false");
        assertEq(eMultisig.canApprove(randomProposalId, david), false, "Should be false");
    }

    function testFuzz_ApproveRevertsIfNotCreated(uint256 randomProposalId) public {
        // Reverts if the proposal doesn't exist

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, randomProposalId, alice)
        );
        eMultisig.approve(randomProposalId);

        // 2
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, randomProposalId, bob));
        eMultisig.approve(randomProposalId);

        // 3
        vm.startPrank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, randomProposalId, carol)
        );
        eMultisig.approve(randomProposalId);

        // 4
        vm.startPrank(david);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, randomProposalId, david)
        );
        eMultisig.approve(randomProposalId);
    }

    function testFuzz_CanExecuteReturnsFalseIfNotCreated(uint256 randomProposalId) public view {
        // returns `false` if the proposal doesn't exist

        assertEq(eMultisig.canExecute(randomProposalId), false, "Should be false");
    }

    function testFuzz_ExecuteRevertsIfNotCreated(uint256 randomProposalId) public {
        // reverts if the proposal doesn't exist

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, randomProposalId));
        eMultisig.execute(randomProposalId, "", actions);
    }

    function test_WhenCallingGetProposalBeingOpen() external givenTheProposalIsOpen {
        // It should return the right values

        // Get proposal returns the right values

        {
            (
                bool executed,
                uint16 approvals,
                EmergencyMultisig.ProposalParameters memory parameters,
                bytes memory encryptedPayloadURI,
                bytes32 publicMetadataUriHash,
                bytes32 destinationActionsHash,
                OptimisticTokenVotingPlugin destinationPlugin
            ) = eMultisig.getProposal(0);

            assertEq(executed, false);
            assertEq(approvals, 0);
            assertEq(parameters.minApprovals, 3);
            assertEq(parameters.snapshotBlock, block.number - 1 - 50); // We made +50 to remove wallets
            assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
            assertEq(encryptedPayloadURI, "ipfs://encrypted");
            assertEq(publicMetadataUriHash, hex"538a79dd5d5741d2d66c0b0ec46e102023a64f8e1e3caeacb6aa4b2b14662a0d");
            assertEq(destinationActionsHash, hex"e212a57e4595f81151b46333ea31e2d5043b53bd562141e1efa1b2778cb3c208");
            assertEq(address(destinationPlugin), address(optimisticPlugin));
        }
        // new proposal

        OptimisticTokenVotingPlugin newOptimisticPlugin;
        (dao, newOptimisticPlugin,, eMultisig,,,,) = builder.build();

        vm.deal(address(dao), 1 ether);

        {
            bytes32 metadataUriHash = keccak256("ipfs://another-public-metadata");

            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0].value = 1 ether;
            actions[0].to = alice;
            actions[0].data = hex"";
            bytes32 actionsHash = eMultisig.hashActions(actions);
            eMultisig.createProposal("ipfs://12340000", metadataUriHash, actionsHash, newOptimisticPlugin, true);

            (
                bool executed,
                uint16 approvals,
                EmergencyMultisig.ProposalParameters memory parameters,
                bytes memory encryptedPayloadURI,
                bytes32 publicMetadataUriHash,
                bytes32 destinationActionsHash,
                OptimisticTokenVotingPlugin destinationPlugin
            ) = eMultisig.getProposal(0);

            assertEq(executed, false);
            assertEq(approvals, 1);
            assertEq(parameters.minApprovals, 3);
            assertEq(parameters.snapshotBlock, block.number - 1);
            assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
            assertEq(encryptedPayloadURI, "ipfs://12340000");
            assertEq(publicMetadataUriHash, metadataUriHash);
            assertEq(destinationActionsHash, actionsHash);
            assertEq(address(destinationPlugin), address(newOptimisticPlugin));
        }
    }

    function test_WhenCallingCanApproveAndApproveBeingOpen() external givenTheProposalIsOpen {
        // It canApprove should return true (when listed on creation, self appointed now)
        bool canApprove = eMultisig.canApprove(0, alice);
        assertEq(canApprove, true, "Alice should be able to approve");

        // It approve should work (when listed on creation, self appointed now)
        // It approve should emit an event (when listed on creation, self appointed now)
        vm.startPrank(alice);
        vm.expectEmit();
        emit Approved(0, alice);
        eMultisig.approve(0);

        // It canApprove should return false (when listed on creation, appointing someone else now)
        canApprove = eMultisig.canApprove(0, bob);
        assertEq(canApprove, false, "Bob should not be able to approve directly");

        // It approve should revert (when listed on creation, appointing someone else now)
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, bob));
        eMultisig.approve(0);

        // It canApprove should return true (when currently appointed by a signer listed on creation)
        canApprove = eMultisig.canApprove(0, randomWallet);
        assertEq(canApprove, true, "Random wallet should be able to approve as appointed");

        // It approve should work (when currently appointed by a signer listed on creation)
        // It approve should emit an event (when currently appointed by a signer listed on creation)
        vm.startPrank(randomWallet);
        vm.expectEmit();
        emit Approved(0, bob); // Note: Event shows the owner, not the appointed wallet
        eMultisig.approve(0);

        // Check approval count
        (, uint16 approvals,,,,,) = eMultisig.getProposal(0);
        assertEq(approvals, 2, "Should have 2 approvals total");

        vm.startPrank(carol);
        assertEq(eMultisig.canApprove(0, carol), true, "Carol should be able to approve");
        eMultisig.approve(0);

        // Should approve, pass but not execute
        bool executed;
        (executed, approvals,,,,,) = eMultisig.getProposal(0);
        assertEq(executed, false, "Should not have executed");
        assertEq(approvals, 3, "Should have 3 approvals total");

        // More approvals
        vm.startPrank(david);
        assertEq(eMultisig.canApprove(0, david), true, "David should be able to approve");
        eMultisig.approve(0);

        (executed, approvals,,,,,) = eMultisig.getProposal(0);
        assertEq(executed, false, "Should not have executed");
        assertEq(approvals, 4, "Should have 4 approvals total");
    }

    function testFuzz_CanApproveReturnsfFalseIfNotListed(address randomWallet) public {
        // returns `false` if the approver is not listed

        {
            // Leaving the deployment for fuzz efficiency
            EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
                onlyListed: false,
                minApprovals: 1,
                signerList: signerList,
                proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
            });
            eMultisig = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );

            vm.roll(block.number + 1);
        }

        uint256 pid = eMultisig.createProposal("", 0, 0, optimisticPlugin, false);

        // ko
        if (randomWallet != alice && randomWallet != bob && randomWallet != carol && randomWallet != david) {
            assertEq(eMultisig.canApprove(pid, randomWallet), false, "Should be false");
        }

        // static ok
        assertEq(eMultisig.canApprove(pid, alice), true, "Should be true");
    }

    function testFuzz_ApproveRevertsIfNotListed(address randomSigner) public {
        // Reverts if the signer is not listed

        builder = new DaoBuilder();
        (,,, eMultisig,,,,) = builder.withMultisigMember(alice).withMinApprovals(1).build();
        uint256 pid = eMultisig.createProposal("", 0, 0, optimisticPlugin, false);

        if (randomSigner == alice) {
            return;
        }

        vm.startPrank(randomSigner);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, randomSigner));
        eMultisig.approve(pid);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, randomSigner));
        eMultisig.approve(pid);
    }

    function test_WhenCallingHasApprovedBeingOpen() external givenTheProposalIsOpen {
        // It hasApproved should return false until approved
        assertEq(eMultisig.hasApproved(0, alice), false, "Should be false before approval");
        assertEq(eMultisig.hasApproved(0, bob), false, "Should be false before approval");
        assertEq(eMultisig.hasApproved(0, randomWallet), false, "Should be false before approval");
        assertEq(eMultisig.hasApproved(0, address(0x5555)), false, "5555 should not have approved");

        // After approvals
        vm.startPrank(alice);
        eMultisig.approve(0);
        assertEq(eMultisig.hasApproved(0, alice), true, "Should be true after approval");

        vm.startPrank(randomWallet);
        eMultisig.approve(0);
        assertEq(eMultisig.hasApproved(0, bob), true, "Should be true after approval by appointed wallet");
        assertEq(eMultisig.hasApproved(0, randomWallet), true, "Should be true after approval");

        assertEq(eMultisig.hasApproved(0, address(0x5555)), false, "5555 should not have approved");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingOpen() external givenTheProposalIsOpen {
        // It canExecute should return false (when listed on creation, self appointed now)
        assertEq(eMultisig.canExecute(0), false, "Should not be executable without approvals");

        vm.deal(address(dao), 1 ether);

        // It execute should revert (when listed on creation, self appointed now)
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"";

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-metadata", actions);

        // Get required approvals
        eMultisig.approve(0);
        vm.startPrank(randomWallet); // Appointed by Bob
        eMultisig.approve(0);
        vm.startPrank(carol);
        eMultisig.approve(0);

        // Now it should be executable
        assertEq(eMultisig.canExecute(0), true, "Should be executable after approvals");
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

        vm.deal(address(dao), 0.5 ether);

        // Create proposal
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0.5 ether;
        actions[0].to = address(carol);
        actions[0].data = hex"";
        bytes32 metadataUriHash = keccak256("ipfs://more-metadata");
        bytes32 actionsHash = eMultisig.hashActions(actions);
        eMultisig.createProposal("ipfs://encrypted", metadataUriHash, actionsHash, optimisticPlugin, false);

        // Remove (later)
        vm.roll(block.number + 50);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;

        vm.startPrank(alice);
        signerList.removeSigners(addrs);

        eMultisig.approve(0);

        _;
    }

    function test_WhenCallingGetProposalBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It should return the right values
        uint256 pid = 0;

        vm.startPrank(randomWallet); // Appointed by Bob
        eMultisig.approve(pid);
        vm.startPrank(carol);
        eMultisig.approve(pid);

        (
            bool executed,
            uint16 approvals,
            EmergencyMultisig.ProposalParameters memory parameters,
            bytes memory encryptedPayloadURI,
            bytes32 publicMetadataUriHash,
            bytes32 destinationActionsHash,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 3);
        assertEq(parameters.snapshotBlock, block.number - 1 - 50); // We made +50 to remove wallets
        assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(encryptedPayloadURI, "ipfs://encrypted");
        assertEq(publicMetadataUriHash, hex"1f4c56b7231f4b1bd019565da91d099db90671db977444a5f3c231dbd6013b27");
        assertEq(destinationActionsHash, hex"ed2486fa6e91780dba02ea013f95f9e84ae8250dcf4c7b62ea5b99fbcf682ee4");
        assertEq(address(destinationPlugin), address(optimisticPlugin));
    }

    function test_WhenCallingCanApproveAndApproveBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It canApprove should return false (when listed on creation, self appointed now)
        assertEq(eMultisig.canApprove(0, alice), false, "Alice should not be able to approve again");

        // It approve should revert (when listed on creation, self appointed now)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, alice));
        eMultisig.approve(0);

        // It canApprove should return true (when currently appointed by a signer listed on creation)
        assertEq(eMultisig.canApprove(0, randomWallet), true, "Random wallet should be able to approve");

        // It approve should work (when currently appointed by a signer listed on creation)
        vm.startPrank(randomWallet);
        eMultisig.approve(0);
    }

    function test_WhenCallingHasApprovedBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It hasApproved should return true for approved addresses
        assertEq(eMultisig.hasApproved(0, alice), true, "Should be true for alice");
        assertEq(eMultisig.hasApproved(0, bob), false, "Should be false for bob");
        assertEq(eMultisig.hasApproved(0, randomWallet), false, "Should be false for randomWallet");
        assertEq(eMultisig.hasApproved(0, address(0x5555)), false, "5555 should not have approved");

        // After additional approval
        vm.startPrank(randomWallet);
        eMultisig.approve(0);
        assertEq(eMultisig.hasApproved(0, bob), true, "Should be true for bob after appointed wallet approves");
        assertEq(eMultisig.hasApproved(0, randomWallet), true, "Should be true after approval");

        assertEq(eMultisig.hasApproved(0, address(0x5555)), false, "5555 should not have approved");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It canExecute should return false (when listed on creation, self appointed now)
        assertEq(eMultisig.canExecute(0), false, "Should not be executable with only one approval");

        // It execute should revert (when listed on creation, self appointed now)
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"";

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-metadata", actions);

        // It canExecute should return false (when currently appointed by a signer listed on creation)
        vm.startPrank(randomWallet);
        assertEq(eMultisig.canExecute(0), false, "Should not be executable with only one approval");

        // It execute should revert (when currently appointed by a signer listed on creation)
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-metadata", actions);
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

        // Create proposal
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"";
        bytes32 metadataUriHash = keccak256("ipfs://the-original-secret-metadata");
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid =
            eMultisig.createProposal("ipfs://more-encrypted", metadataUriHash, actionsHash, optimisticPlugin, false);

        // Remove (later)
        vm.roll(block.number + 50);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;

        vm.startPrank(alice);
        signerList.removeSigners(addrs);

        eMultisig.approve(pid);

        vm.startPrank(randomWallet);
        eMultisig.approve(pid);

        vm.startPrank(carol);
        eMultisig.approve(pid);

        vm.startPrank(alice);

        _;
    }

    function test_WhenCallingGetProposalBeingPassed() external givenTheProposalPassed {
        // It should return the right values

        // Retrieve the proposal
        (
            bool executed,
            uint16 approvals,
            EmergencyMultisig.ProposalParameters memory parameters,
            bytes memory encryptedPayloadURI,
            bytes32 publicMetadataUriHash,
            bytes32 destinationActionsHash,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = eMultisig.getProposal(0);

        // Assert the proposal is not executed
        assertEq(executed, false, "Proposal should not be executed");

        // Assert the number of approvals
        assertEq(approvals, 3, "Approvals should be 3");

        // Assert the proposal parameters
        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1 - 50, "Incorrect snapshotBlock");
        assertEq(
            parameters.expirationDate,
            block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD,
            "Incorrect expirationDate"
        );

        // Assert the encrypted payload URI
        assertEq(encryptedPayloadURI, "ipfs://more-encrypted", "Incorrect encryptedPayloadURI");

        // Assert the public metadata URI hash
        assertEq(
            publicMetadataUriHash, keccak256("ipfs://the-original-secret-metadata"), "Incorrect publicMetadataUriHash"
        );

        // Assert the destination actions hash
        assertEq(
            destinationActionsHash,
            hex"e212a57e4595f81151b46333ea31e2d5043b53bd562141e1efa1b2778cb3c208",
            "Incorrect destinationActionsHash"
        );

        // Assert the destination plugin
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destinationPlugin");
    }

    function test_WhenCallingCanApproveAndApproveBeingPassed() external givenTheProposalPassed {
        // It canApprove should return false (when listed on creation, self appointed now)
        // vm.startPrank(alice);
        assertEq(eMultisig.canApprove(0, alice), false, "Alice should not be able to approve");
        // It approve should revert (when listed on creation, self appointed now)
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, alice));
        eMultisig.approve(0);

        // It canApprove should return false (when listed on creation, appointing someone else now)
        vm.startPrank(bob);
        assertEq(eMultisig.canApprove(0, bob), false, "Bob should not be able to approve");
        // It approve should revert (when listed on creation, appointing someone else now)
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, bob));
        eMultisig.approve(0);

        // It canApprove should return false (when currently appointed by a signer listed on creation)
        vm.startPrank(randomWallet);
        assertEq(eMultisig.canApprove(0, randomWallet), false, "Random wallet should not be able to approve");
        // It approve should revert (when currently appointed by a signer listed on creation)
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, randomWallet));
        eMultisig.approve(0);

        // It canApprove should return false (when unlisted on creation, unappointed now)
        vm.startPrank(address(0x1234));
        assertEq(eMultisig.canApprove(0, address(0x1234)), false, "Random wallet should not be able to approve");
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, address(0x1234)));
        eMultisig.approve(0);
    }

    function test_WhenCallingHasApprovedBeingPassed() external givenTheProposalPassed {
        // It hasApproved should return false until approved

        assertEq(eMultisig.hasApproved(0, alice), true, "Alice should have approved");
        assertEq(eMultisig.hasApproved(0, bob), true, "Bob should have approved");
        assertEq(eMultisig.hasApproved(0, randomWallet), true, "Should be true");
        assertEq(eMultisig.hasApproved(0, address(0x5555)), false, "5555 should not have approved");
    }

    function test_WhenCallingCanExecuteOrExecuteWithModifiedDataBeingPassed() external givenTheProposalPassed {
        // It execute should revert with modified metadata
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"";

        // vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.InvalidMetadataUri.selector, 0));
        eMultisig.execute(0, "ipfs://modified-metadata-1234", actions);

        // It execute should revert with modified actions
        actions[0].value = 2 ether; // Modify action
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.InvalidActions.selector, 0));
        eMultisig.execute(0, "ipfs://the-original-secret-metadata", actions);

        // It execute should work with matching data
        actions[0].value = 1 ether; // Reset action
        eMultisig.execute(0, "ipfs://the-original-secret-metadata", actions);
    }

    function test_WhenCallingCanExecuteOrExecuteBeingPassed() external givenTheProposalPassed {
        // It canExecute should return true, always
        assertEq(eMultisig.canExecute(0), true, "Proposal should be executable");

        // It execute should work, when called by anyone with the actions
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"";

        // It execute should emit an event, when called by anyone with the actions
        vm.expectEmit();
        emit Executed(0);

        // It A ProposalCreated event is emitted on the destination plugin
        uint256 targetPid = (block.timestamp << 128) | (block.timestamp << 64);
        vm.expectEmit();
        emit ProposalCreated(
            targetPid,
            address(eMultisig),
            uint64(block.timestamp),
            uint64(block.timestamp),
            "ipfs://the-original-secret-metadata",
            actions,
            0
        );

        eMultisig.execute(0, "ipfs://the-original-secret-metadata", actions);

        // It execute recreates the proposal on the destination plugin

        bool open;
        bool executed;
        OptimisticTokenVotingPlugin.ProposalParameters memory parameters;
        uint256 vetoTally;
        bytes memory metadataUri;
        IDAO.Action[] memory retrievedActions;
        uint256 allowFailureMap;

        (open, executed, parameters, vetoTally, metadataUri, retrievedActions, allowFailureMap) =
            optimisticPlugin.getProposal(targetPid);

        // It The parameters of the recreated proposal match the hash of the executed one
        assertEq(open, false, "Should not be open");
        // It Execution is immediate on the destination plugin
        assertEq(executed, true, "Should be executed");
        assertEq(vetoTally, 0, "Should be 0");

        assertEq(parameters.vetoEndDate, block.timestamp, "Incorrect vetoEndDate");
        assertEq(metadataUri, "ipfs://the-original-secret-metadata", "Incorrect target metadataUri");

        assertEq(retrievedActions.length, 1, "Should be 3");

        assertEq(retrievedActions[0].to, bob, "Incorrect to");
        assertEq(retrievedActions[0].value, 1 ether, "Incorrect value");
        assertEq(retrievedActions[0].data, hex"", "Incorrect data");

        assertEq(allowFailureMap, 0, "Should be 0");
    }

    function test_GivenTaikoL1IsIncompatible() external givenTheProposalPassed {
        // It executes successfully, regardless

        (dao, optimisticPlugin,, eMultisig,,,,) = builder.withIncompatibleTaikoL1().build();

        vm.deal(address(dao), 4 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        bytes32 metadataUriHash = keccak256("ipfs://");
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", metadataUriHash, actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);
        (bool executed,,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        (executed,,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);
        (executed,,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        vm.startPrank(randomWallet);
        eMultisig.execute(pid, "ipfs://", actions);
        (executed,,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        assertEq(bob.balance, 1 ether, "Incorrect balance");
        assertEq(address(dao).balance, 3 ether, "Incorrect balance");
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

        // Create proposal
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0.8 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"";
        bytes32 metadataUriHash = keccak256("ipfs://the-orig-metadata");
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid =
            eMultisig.createProposal("ipfs://encrypted", metadataUriHash, actionsHash, optimisticPlugin, false);

        // Remove (later)
        vm.roll(block.number + 50);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;

        vm.startPrank(alice);
        signerList.removeSigners(addrs);

        eMultisig.approve(pid);

        vm.startPrank(randomWallet);
        eMultisig.approve(pid);

        vm.startPrank(carol);
        eMultisig.approve(pid);

        eMultisig.execute(pid, "ipfs://the-orig-metadata", actions);

        vm.startPrank(alice);

        _;
    }

    function test_WhenCallingGetProposalBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It should return the right values
        (
            bool executed,
            uint16 approvals,
            EmergencyMultisig.ProposalParameters memory parameters,
            bytes memory encryptedPayloadURI,
            bytes32 publicMetadataUriHash,
            bytes32 destinationActionsHash,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = eMultisig.getProposal(0);

        assertEq(executed, true, "Proposal should be executed");
        assertEq(approvals, 3, "Approvals should be 3");

        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1 - 50, "Incorrect snapshotBlock");
        assertEq(
            parameters.expirationDate,
            block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD,
            "Incorrect expirationDate"
        );
        assertEq(encryptedPayloadURI, "ipfs://encrypted");
        assertEq(publicMetadataUriHash, keccak256("ipfs://the-orig-metadata"));
        assertEq(destinationActionsHash, hex"c85c954206700a1f89dfd6599c77677611fdbc8dcb7f15d44158e10b46d13391");
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destinationPlugin");
    }

    function test_WhenCallingCanApproveAndApproveBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        assertEq(eMultisig.canApprove(0, alice), false, "Alice should not be able to approve");
        assertEq(eMultisig.canApprove(0, bob), false, "Bob should not be able to approve");
        assertEq(eMultisig.canApprove(0, randomWallet), false, "Random wallet should not be able to approve");
        assertEq(eMultisig.canApprove(0, address(0x890a)), false, "Random wallet should not be able to approve");

        // It approve should revert (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, alice));
        eMultisig.approve(0);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, bob));
        eMultisig.approve(0);

        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, randomWallet));
        eMultisig.approve(0);

        vm.startPrank(address(0x890a));
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, address(0x890a)));
        eMultisig.approve(0);
    }

    function test_WhenCallingHasApprovedBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It hasApproved should return false until approved

        // Assert hasApproved returns true for those who approved
        assertEq(eMultisig.hasApproved(0, alice), true, "Alice should have approved");
        assertEq(eMultisig.hasApproved(0, bob), true, "Bob should have approved");
        assertEq(eMultisig.hasApproved(0, randomWallet), true, "Random wallet should have approved");
        assertEq(eMultisig.hasApproved(0, address(0x5555)), false, "5555 should not have approved");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)
        // vm.startPrank(alice);
        assertEq(eMultisig.canExecute(0), false, "Proposal should not be executable");
        vm.startPrank(bob);
        assertEq(eMultisig.canExecute(0), false, "Proposal should not be executable");
        vm.startPrank(randomWallet);
        assertEq(eMultisig.canExecute(0), false, "Proposal should not be executable");
        vm.startPrank(address(0x7890));
        assertEq(eMultisig.canExecute(0), false, "Proposal should not be executable");

        // It execute should revert (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It execute should revert (when unlisted on creation, unappointed now)
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 0.8 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"";

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-orig-metadata", actions);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-orig-metadata", actions);

        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-orig-metadata", actions);

        vm.startPrank(address(0x7890));
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-orig-metadata", actions);
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

        // Create proposal
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1.5 ether;
        actions[0].to = address(carol);
        actions[0].data = hex"";
        bytes32 metadataUriHash = keccak256("ipfs://the-metadata");
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid =
            eMultisig.createProposal("ipfs://encrypted", metadataUriHash, actionsHash, optimisticPlugin, false);

        // Remove (later)
        vm.roll(block.number + 50);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;

        vm.startPrank(alice);
        signerList.removeSigners(addrs);

        eMultisig.approve(pid);

        vm.startPrank(randomWallet);
        eMultisig.approve(pid);

        vm.warp(block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);

        vm.startPrank(alice);

        _;
    }

    function test_WhenCallingGetProposalBeingExpired() external givenTheProposalExpired {
        // It should return the right values
        (
            bool executed,
            uint16 approvals,
            EmergencyMultisig.ProposalParameters memory parameters,
            bytes memory encryptedPayloadURI,
            bytes32 publicMetadataUriHash,
            bytes32 destinationActionsHash,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = eMultisig.getProposal(0);

        // Assert the proposal is not executed
        assertEq(executed, false, "Proposal should not be executed");

        // Assert the number of approvals
        assertEq(approvals, 2, "Approvals should be 2");

        // Assert the proposal parameters
        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1 - 50, "Incorrect snapshotBlock");
        assertEq(
            parameters.expirationDate,
            block.timestamp, // we just moved to it
            "Incorrect expirationDate"
        );

        // Assert the encrypted payload URI
        assertEq(encryptedPayloadURI, "ipfs://encrypted", "Incorrect encryptedPayloadURI");

        // Assert the public metadata URI hash
        assertEq(publicMetadataUriHash, keccak256("ipfs://the-metadata"), "Incorrect publicMetadataUriHash");

        // Assert the destination actions hash
        assertEq(
            destinationActionsHash,
            hex"3626b3f254463d63d9bd5ff77ff99d2691b20f0db6347f685befae593d8f4e6f",
            "Incorrect destinationActionsHash"
        );

        // Assert the destination plugin
        assertEq(address(destinationPlugin), address(optimisticPlugin), "Incorrect destinationPlugin");
    }

    function test_WhenCallingCanApproveAndApproveBeingExpired() external givenTheProposalExpired {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        assertEq(eMultisig.canApprove(0, alice), false, "Alice should not be able to approve");
        assertEq(eMultisig.canApprove(0, bob), false, "Bob should not be able to approve");
        assertEq(eMultisig.canApprove(0, randomWallet), false, "Random wallet should not be able to approve");
        assertEq(eMultisig.canApprove(0, address(0x5555)), false, "Random wallet should not be able to approve");

        // It approve should revert (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, alice));
        eMultisig.approve(0);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, bob));
        eMultisig.approve(0);

        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, randomWallet));
        eMultisig.approve(0);

        vm.startPrank(address(0x5555));
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, 0, address(0x5555)));
        eMultisig.approve(0);
    }

    function test_WhenCallingHasApprovedBeingExpired() external givenTheProposalExpired {
        // It hasApproved should return false until approved

        assertEq(eMultisig.hasApproved(0, alice), true, "Alice should have approved");
        assertEq(eMultisig.hasApproved(0, bob), true, "Bob should have approved");
        assertEq(eMultisig.hasApproved(0, randomWallet), true, "Random wallet should have approved");
        assertEq(eMultisig.hasApproved(0, address(0x5555)), false, "5555 should not have approved");
    }

    function test_WhenCallingCanExecuteOrExecuteBeingExpired() external givenTheProposalExpired {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)

        // vm.startPrank(alice);
        assertEq(eMultisig.canExecute(0), false, "Proposal should not be executable");
        vm.startPrank(bob);
        assertEq(eMultisig.canExecute(0), false, "Proposal should not be executable");
        vm.startPrank(randomWallet);
        assertEq(eMultisig.canExecute(0), false, "Proposal should not be executable");
        vm.startPrank(address(0x5555));
        assertEq(eMultisig.canExecute(0), false, "Proposal should not be executable");

        // It execute should revert (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It execute should revert (when unlisted on creation, unappointed now)
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1.5 ether;
        actions[0].to = address(carol);
        actions[0].data = hex"";

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-metadata", actions);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-metadata", actions);

        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-metadata", actions);

        vm.startPrank(address(0x5555));
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, 0));
        eMultisig.execute(0, "ipfs://the-metadata", actions);
    }
}
