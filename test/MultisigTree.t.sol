// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {Multisig} from "../src/Multisig.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {SignerList, UPDATE_SIGNER_LIST_PERMISSION_ID} from "../src/SignerList.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {createProxyAndCall} from "../src/helpers/proxy.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";
import {IPlugin} from "@aragon/osx/core/plugin/IPlugin.sol";
import {IMultisig} from "../src/interfaces/IMultisig.sol";

uint64 constant MULTISIG_PROPOSAL_EXPIRATION_PERIOD = 10 days;

contract MultisigTest is AragonTest {
    SignerList signerList;
    DaoBuilder builder;
    DAO dao;
    Multisig multisig;
    OptimisticTokenVotingPlugin optimisticPlugin;

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
    // Multisig proposal
    event ProposalCreated(uint256 indexed proposalId, address indexed creator, bytes encryptedPayloadURI);
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

        builder = new DaoBuilder();
        (dao,, multisig,,, signerList,,) = builder.withMultisigMember(alice).withMultisigMember(bob).withMultisigMember(
            carol
        ).withMultisigMember(david).withMinApprovals(3).build();
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
        assertEq(currentDestinationProposalDuration, 10 days);
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
        assertEq(destMinDuration, 10 days, "Incorrect destMinDuration");
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
            endDate: uint64(block.timestamp) + 10 days,
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
            endDate: uint64(block.timestamp) + 10 days,
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
            endDate: uint64(block.timestamp) + 10 days,
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
        vm.skip(true);
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
        vm.skip(true);
    }

    function test_GivenCreationCallerIsAppointedByAFormerSigner()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It reverts
        vm.skip(true);
    }

    function test_GivenCreationCallerIsListedAndSelfAppointed()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It creates the proposal
        vm.skip(true);
    }

    function test_GivenCreationCallerIsListedAppointingSomeoneElseNow()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It creates the proposal
        vm.skip(true);
    }

    function test_GivenCreationCallerIsAppointedByACurrentSigner()
        external
        whenCallingCreateProposal
        givenOnlyListedIsTrue
    {
        // It creates the proposal
        vm.skip(true);
    }

    function test_GivenApproveProposalIsTrue() external whenCallingCreateProposal {
        // It creates and calls approval in one go
        vm.skip(true);
    }

    function test_GivenApproveProposalIsFalse() external whenCallingCreateProposal {
        // It only creates the proposal
        vm.skip(true);
    }

    modifier givenTheProposalIsNotCreated() {
        _;
    }

    function test_WhenCallingGetProposalBeingUncreated() external givenTheProposalIsNotCreated {
        // It should return empty values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveBeingUncreated() external givenTheProposalIsNotCreated {
        // It canApprove should return false (when currently listed and self appointed)
        // It approve should revert (when currently listed and self appointed)
        // It canApprove should return false (when currently listed, appointing someone else now)
        // It approve should revert (when currently listed, appointing someone else now)
        // It canApprove should return false (when appointed by a listed signer)
        // It approve should revert (when appointed by a listed signer)
        // It canApprove should return false (when currently unlisted and unappointed)
        // It approve should revert (when currently unlisted and unappointed)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedBeingUncreated() external givenTheProposalIsNotCreated {
        // It hasApproved should always return false
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteBeingUncreated() external givenTheProposalIsNotCreated {
        // It canExecute should return false (when currently listed and self appointed)
        // It execute should revert (when currently listed and self appointed)
        // It canExecute should return false (when currently listed, appointing someone else now)
        // It execute should revert (when currently listed, appointing someone else now)
        // It canExecute should return false (when appointed by a listed signer)
        // It execute should revert (when appointed by a listed signer)
        // It canExecute should return false (when currently unlisted and unappointed)
        // It execute should revert (when currently unlisted and unappointed)
        vm.skip(true);
    }

    modifier givenTheProposalIsOpen() {
        _;
    }

    function test_WhenCallingGetProposalBeingOpen() external givenTheProposalIsOpen {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveBeingOpen() external givenTheProposalIsOpen {
        // It canApprove should return true (when listed on creation, self appointed now)
        // It approve should work (when listed on creation, self appointed now)
        // It approve should emit an event (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It canApprove should return true (when currently appointed by a signer listed on creation)
        // It approve should work (when currently appointed by a signer listed on creation)
        // It approve should emit an event (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    function test_WhenCallingApproveWithTryExecutionAndAlmostPassedBeingOpen() external givenTheProposalIsOpen {
        // It approve should also execute the proposal
        // It approve should emit an Executed event
        // It approve recreates the proposal on the destination plugin
        // It The parameters of the recreated proposal match those of the approved one
        // It A ProposalCreated event is emitted on the destination plugin
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedBeingOpen() external givenTheProposalIsOpen {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteBeingOpen() external givenTheProposalIsOpen {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)
        // It execute should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    modifier givenTheProposalWasApprovedByTheAddress() {
        _;
    }

    function test_WhenCallingGetProposalBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It approve should revert (when currently appointed by a signer listed on creation)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteBeingApproved() external givenTheProposalWasApprovedByTheAddress {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It execute should revert (when currently appointed by a signer listed on creation)
        vm.skip(true);
    }

    modifier givenTheProposalPassed() {
        _;
    }

    function test_WhenCallingGetProposalBeingPassed() external givenTheProposalPassed {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveBeingPassed() external givenTheProposalPassed {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedBeingPassed() external givenTheProposalPassed {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteBeingPassed() external givenTheProposalPassed {
        // It canExecute should return true, always
        // It execute should work, when called by anyone
        // It execute should emit an event, when called by anyone
        // It execute recreates the proposal on the destination plugin
        // It The parameters of the recreated proposal match those of the executed one
        // It The proposal duration on the destination plugin matches the multisig settings
        // It A ProposalCreated event is emitted on the destination plugin
        vm.skip(true);
    }

    function test_GivenTaikoL1IsIncompatible() external givenTheProposalPassed {
        // It executes successfully, regardless
        vm.skip(true);
    }

    modifier givenTheProposalIsAlreadyExecuted() {
        _;
    }

    function test_WhenCallingGetProposalBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteBeingExecuted() external givenTheProposalIsAlreadyExecuted {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)
        // It execute should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    modifier givenTheProposalExpired() {
        _;
    }

    function test_WhenCallingGetProposalBeingExpired() external givenTheProposalExpired {
        // It should return the right values
        vm.skip(true);
    }

    function test_WhenCallingCanApproveAndApproveBeingExpired() external givenTheProposalExpired {
        // It canApprove should return false (when listed on creation, self appointed now)
        // It approve should revert (when listed on creation, self appointed now)
        // It canApprove should return false (when listed on creation, appointing someone else now)
        // It approve should revert (when listed on creation, appointing someone else now)
        // It canApprove should return false (when currently appointed by a signer listed on creation)
        // It approve should revert (when currently appointed by a signer listed on creation)
        // It canApprove should return false (when unlisted on creation, unappointed now)
        // It approve should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }

    function test_WhenCallingHasApprovedBeingExpired() external givenTheProposalExpired {
        // It hasApproved should return false until approved
        vm.skip(true);
    }

    function test_WhenCallingCanExecuteAndExecuteBeingExpired() external givenTheProposalExpired {
        // It canExecute should return false (when listed on creation, self appointed now)
        // It execute should revert (when listed on creation, self appointed now)
        // It canExecute should return false (when listed on creation, appointing someone else now)
        // It execute should revert (when listed on creation, appointing someone else now)
        // It canExecute should return false (when currently appointed by a signer listed on creation)
        // It execute should revert (when currently appointed by a signer listed on creation)
        // It canExecute should return false (when unlisted on creation, unappointed now)
        // It execute should revert (when unlisted on creation, unappointed now)
        vm.skip(true);
    }
}
