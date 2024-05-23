// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {StandardProposalCondition} from "../src/conditions/StandardProposalCondition.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {Multisig} from "../src/Multisig.sol";
import {EmergencyMultisig, EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD} from "../src/EmergencyMultisig.sol";
import {IEmergencyMultisig} from "../src/interfaces/IEmergencyMultisig.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";
import {IPlugin} from "@aragon/osx/core/plugin/IPlugin.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {createProxyAndCall} from "./helpers/proxy.sol";

contract EmergencyMultisigTest is AragonTest {
    DaoBuilder builder;

    DAO dao;
    EmergencyMultisig eMultisig;
    Multisig stdMultisig;
    OptimisticTokenVotingPlugin optimisticPlugin;

    // Events/errors to be tested here (duplicate)
    event MultisigSettingsUpdated(bool onlyListed, uint16 indexed minApprovals, Addresslist addresslistSource);
    event MembersAdded(address[] members);
    event MembersRemoved(address[] members);

    error InvalidAddresslistUpdate(address member);
    error InvalidActions(uint256 proposalId);

    // Multisig's event
    event ProposalCreated(
        uint256 indexed proposalId, address indexed creator, bytes encryptedPayloadURI, bytes32 destinationActionsHash
    );
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
        (dao, optimisticPlugin, stdMultisig, eMultisig,,) = builder.withMultisigMember(alice).withMultisigMember(bob)
            .withMultisigMember(carol).withMultisigMember(david).withMinApprovals(3).withMinDuration(0).build();
    }

    function test_RevertsIfTryingToReinitialize() public {
        // Deploy a new stdMultisig instance
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: stdMultisig});

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // Reinitialize should fail
        vm.expectRevert("Initializable: contract is already initialized");
        eMultisig.initialize(dao, settings);
    }

    function test_InitializeSetsMinApprovals() public {
        // 2
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 2, addresslistSource: stdMultisig});

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        (, uint16 minApprovals,) = eMultisig.multisigSettings();
        assertEq(minApprovals, uint16(2), "Incorrect minApprovals");

        // Redeploy with 1
        settings.minApprovals = 1;

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        (, minApprovals,) = eMultisig.multisigSettings();
        assertEq(minApprovals, uint16(1), "Incorrect minApprovals");
    }

    function test_InitializeSetsOnlyListed() public {
        // Deploy with true
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: stdMultisig});

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        (bool onlyListed,,) = eMultisig.multisigSettings();
        assertEq(onlyListed, true, "Incorrect onlyListed");

        // Redeploy with false
        settings.onlyListed = false;

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        (onlyListed,,) = eMultisig.multisigSettings();
        assertEq(onlyListed, false, "Incorrect onlyListed");
    }

    function test_InitializeSetsAddresslistSource() public {
        // Deploy the default stdMultisig as source
        EmergencyMultisig.MultisigSettings memory emSettings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: stdMultisig});

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, emSettings))
            )
        );

        (,, Addresslist givenAddressListSource) = eMultisig.multisigSettings();
        assertEq(address(givenAddressListSource), address(stdMultisig), "Incorrect addresslistSource");

        // Redeploy with a new addresslist source
        (,, Multisig newMultisig,,,) = builder.build();

        emSettings.addresslistSource = newMultisig;

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, emSettings))
            )
        );

        (,, givenAddressListSource) = eMultisig.multisigSettings();
        assertEq(address(givenAddressListSource), address(emSettings.addresslistSource), "Incorrect addresslistSource");
    }

    function test_ShouldEmitMultisigSettingsUpdatedOnInstall() public {
        // Deploy with true/3/default
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: stdMultisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, uint16(3), stdMultisig);

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // Deploy with false/2/new

        (,, Multisig newMultisig,,,) = builder.build();

        settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 2, addresslistSource: newMultisig});
        vm.expectEmit();
        emit MultisigSettingsUpdated(false, uint16(2), newMultisig);

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    // INTERFACES

    function test_DoesntSupportTheEmptyInterface() public view {
        bool supported = eMultisig.supportsInterface(0);
        assertEq(supported, false, "Should not support the empty interface");
    }

    function test_SupportsIERC165Upgradeable() public view {
        bool supported = eMultisig.supportsInterface(type(IERC165Upgradeable).interfaceId);
        assertEq(supported, true, "Should support IERC165Upgradeable");
    }

    function test_SupportsIPlugin() public view {
        bool supported = eMultisig.supportsInterface(type(IPlugin).interfaceId);
        assertEq(supported, true, "Should support IPlugin");
    }

    function test_SupportsIProposal() public view {
        bool supported = eMultisig.supportsInterface(type(IProposal).interfaceId);
        assertEq(supported, true, "Should support IProposal");
    }

    function test_SupportsIMembership() public view {
        bool supported = eMultisig.supportsInterface(type(IMembership).interfaceId);
        assertEq(supported, true, "Should support IMembership");
    }

    function test_SupportsIEmergencyMultisig() public view {
        bool supported = eMultisig.supportsInterface(type(IEmergencyMultisig).interfaceId);
        assertEq(supported, true, "Should support IEmergencyMultisig");
    }

    // UPDATE MULTISIG SETTINGS

    function test_ShouldntAllowMinApprovalsHigherThenAddrListLength() public {
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5,
            addresslistSource: stdMultisig // Greater than 4 members
        });

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 4, 5));

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // Retry with onlyListed false
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 6,
            addresslistSource: stdMultisig // Greater than 4 members
        });
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 4, 6));
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    function test_ShouldNotAllowMinApprovalsZero() public {
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 0, addresslistSource: stdMultisig});

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 1, 0));

        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // Retry with onlyListed false
        settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 0, addresslistSource: stdMultisig});
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 1, 0));
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    function test_ShouldEmitMultisigSettingsUpdated() public {
        dao.grant(address(eMultisig), address(alice), eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // 1
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 1, addresslistSource: stdMultisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 1, stdMultisig);
        eMultisig.updateMultisigSettings(settings);

        // 2
        (,, Multisig newMultisig,,,) = builder.build();

        settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 2, addresslistSource: newMultisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 2, newMultisig);
        eMultisig.updateMultisigSettings(settings);

        // 3
        (,, newMultisig,,,) = builder.build();

        settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 3, addresslistSource: newMultisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 3, newMultisig);
        eMultisig.updateMultisigSettings(settings);

        // 4
        settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 4, addresslistSource: stdMultisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 4, stdMultisig);
        eMultisig.updateMultisigSettings(settings);
    }

    function test_UpdateSettingsShouldRevertWithInvalidAddressSource() public {
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // ko
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            addresslistSource: Multisig(address(dao))
        });
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.InvalidAddressListSource.selector, address(dao)));
        eMultisig.updateMultisigSettings(settings);

        // ko 2
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 1,
            addresslistSource: Multisig(address(optimisticPlugin))
        });
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyMultisig.InvalidAddressListSource.selector, address(optimisticPlugin))
        );
        eMultisig.updateMultisigSettings(settings);

        // ok
        (,, Multisig newMultisig,,,) = builder.build();
        settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 1, addresslistSource: newMultisig});
        eMultisig.updateMultisigSettings(settings);
    }

    function test_onlyWalletWithPermissionsCanUpdateSettings() public {
        (,, Multisig newMultisig,,,) = builder.build();

        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 1, addresslistSource: newMultisig});
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
        (bool onlyListed, uint16 minApprovals, Addresslist currentSource) = eMultisig.multisigSettings();
        assertEq(onlyListed, true);
        assertEq(minApprovals, 3);
        assertEq(address(currentSource), address(stdMultisig));

        // Retry with the permission
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 1, newMultisig);
        eMultisig.updateMultisigSettings(settings);
    }

    function test_IsMemberShouldReturnWhenApropriate() public {
        assertEq(eMultisig.isMember(alice), true, "Should be a member");
        assertEq(eMultisig.isMember(bob), true, "Should be a member");
        assertEq(eMultisig.isMember(carol), true, "Should be a member");
        assertEq(eMultisig.isMember(david), true, "Should be a member");

        dao.grant(address(stdMultisig), alice, stdMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        address[] memory signers = new address[](1);
        signers[0] = bob;
        stdMultisig.removeAddresses(signers);

        assertEq(eMultisig.isMember(alice), true, "Should be a member");
        assertEq(eMultisig.isMember(bob), false, "Should not be a member");
        assertEq(eMultisig.isMember(carol), true, "Should be a member");
        assertEq(eMultisig.isMember(david), true, "Should be a member");

        // 2
        stdMultisig.addAddresses(signers); // Add Bob back
        signers[0] = alice;
        stdMultisig.removeAddresses(signers);

        assertEq(eMultisig.isMember(alice), false, "Should not be a member");
        assertEq(eMultisig.isMember(bob), true, "Should be a member");
        assertEq(eMultisig.isMember(carol), true, "Should be a member");
        assertEq(eMultisig.isMember(david), true, "Should be a member");

        // 3
        stdMultisig.addAddresses(signers); // Add Alice back
        signers[0] = carol;
        stdMultisig.removeAddresses(signers);

        assertEq(eMultisig.isMember(alice), true, "Should be a member");
        assertEq(eMultisig.isMember(bob), true, "Should be a member");
        assertEq(eMultisig.isMember(carol), false, "Should not be a member");
        assertEq(eMultisig.isMember(david), true, "Should be a member");

        // 4
        stdMultisig.addAddresses(signers); // Add Carol back
        signers[0] = david;
        stdMultisig.removeAddresses(signers);

        assertEq(eMultisig.isMember(alice), true, "Should be a member");
        assertEq(eMultisig.isMember(bob), true, "Should be a member");
        assertEq(eMultisig.isMember(carol), true, "Should be a member");
        assertEq(eMultisig.isMember(david), false, "Should not be a member");
    }

    function test_IsMemberIsListedShouldReturnTheSameValue() public {
        assertEq(stdMultisig.isListed(alice), eMultisig.isMember(alice), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(bob), eMultisig.isMember(bob), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(carol), eMultisig.isMember(carol), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(david), eMultisig.isMember(david), "isMember isListed should be equal");

        dao.grant(address(stdMultisig), alice, stdMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        address[] memory signers = new address[](1);
        signers[0] = alice;
        stdMultisig.removeAddresses(signers);

        assertEq(stdMultisig.isListed(alice), eMultisig.isMember(alice), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(bob), eMultisig.isMember(bob), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(carol), eMultisig.isMember(carol), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(david), eMultisig.isMember(david), "isMember isListed should be equal");

        // 2
        stdMultisig.addAddresses(signers); // Add Alice back
        signers[0] = bob;
        stdMultisig.removeAddresses(signers);

        assertEq(stdMultisig.isListed(alice), eMultisig.isMember(alice), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(bob), eMultisig.isMember(bob), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(carol), eMultisig.isMember(carol), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(david), eMultisig.isMember(david), "isMember isListed should be equal");

        // 3
        stdMultisig.addAddresses(signers); // Add Bob back
        signers[0] = carol;
        stdMultisig.removeAddresses(signers);

        assertEq(stdMultisig.isListed(alice), eMultisig.isMember(alice), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(bob), eMultisig.isMember(bob), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(carol), eMultisig.isMember(carol), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(david), eMultisig.isMember(david), "isMember isListed should be equal");

        // 4
        stdMultisig.addAddresses(signers); // Add Carol back
        signers[0] = david;
        stdMultisig.removeAddresses(signers);

        assertEq(stdMultisig.isListed(alice), eMultisig.isMember(alice), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(bob), eMultisig.isMember(bob), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(carol), eMultisig.isMember(carol), "isMember isListed should be equal");
        assertEq(stdMultisig.isListed(david), eMultisig.isMember(david), "isMember isListed should be equal");
    }

    function testFuzz_IsMemberIsFalseByDefault(uint256 _randomEntropy) public {
        // Deploy a new stdMultisig instance
        Multisig.MultisigSettings memory mSettings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](1);
        signers[0] = address(0x0); // 0x0... would be a member but the chance is negligible

        stdMultisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, mSettings)))
        );
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 1, addresslistSource: stdMultisig});
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        assertEq(
            eMultisig.isMember(vm.addr(uint256(keccak256(abi.encodePacked(_randomEntropy))))), false, "Should be false"
        );
    }

    function testFuzz_PermissionedUpdateSettings(address randomAccount) public {
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        (bool onlyListed, uint16 minApprovals, Addresslist addresslistSource) = eMultisig.multisigSettings();
        assertEq(minApprovals, 3, "Should be 3");
        assertEq(onlyListed, true, "Should be true");
        assertEq(address(addresslistSource), address(stdMultisig), "Incorrect addresslistSource");

        // in
        (,, Multisig newMultisig,,,) = builder.build();
        EmergencyMultisig.MultisigSettings memory newSettings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 2, addresslistSource: newMultisig});
        eMultisig.updateMultisigSettings(newSettings);

        Addresslist givenAddresslistSource;
        (onlyListed, minApprovals, givenAddresslistSource) = eMultisig.multisigSettings();
        assertEq(minApprovals, 2, "Should be 2");
        assertEq(onlyListed, false, "Should be false");
        assertEq(address(givenAddresslistSource), address(newMultisig), "Incorrect addresslistSource");

        // out
        newSettings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 1, addresslistSource: stdMultisig});
        eMultisig.updateMultisigSettings(newSettings);
        (onlyListed, minApprovals, givenAddresslistSource) = eMultisig.multisigSettings();
        assertEq(minApprovals, 1, "Should be 1");
        assertEq(onlyListed, true, "Should be true");
        assertEq(address(givenAddresslistSource), address(stdMultisig), "Incorrect addresslistSource");

        vm.roll(block.number + 1);

        // someone else
        if (randomAccount != alice && randomAccount != address(0)) {
            vm.startPrank(randomAccount);

            (,, newMultisig,,,) = builder.build();
            newSettings =
                EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 4, addresslistSource: newMultisig});

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

            (onlyListed, minApprovals, givenAddresslistSource) = eMultisig.multisigSettings();
            assertEq(minApprovals, 1, "Should still be 1");
            assertEq(onlyListed, true, "Should still be true");
            assertEq(address(givenAddresslistSource), address(stdMultisig), "Should still be stdMultisig");
        }
    }

    // PROPOSAL CREATION

    function test_IncrementsTheProposalCounter() public {
        // increments the proposal counter
        assertEq(eMultisig.proposalCount(), 0, "Should have no proposals");

        // 1
        eMultisig.createProposal(
            "ipfs://",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            false
        );

        assertEq(eMultisig.proposalCount(), 1, "Should have 1 proposal");

        // 2
        eMultisig.createProposal(
            "ipfs://more",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            true
        );

        assertEq(eMultisig.proposalCount(), 2, "Should have 2 proposals");
    }

    function test_CreatesAndReturnsUniqueProposalIds() public {
        // creates unique proposal IDs for each proposal

        // 1
        uint256 pid = eMultisig.createProposal(
            "", bytes32(0x1234000000000000000000000000000000000000000000000000000000000000), optimisticPlugin, true
        );

        assertEq(pid, 0, "Should be 0");

        // 2
        pid = eMultisig.createProposal(
            "ipfs://",
            bytes32(0x0000567800000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            false
        );

        assertEq(pid, 1, "Should be 1");

        // 3
        pid = eMultisig.createProposal(
            "ipfs://more",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            true
        );

        assertEq(pid, 2, "Should be 2");
    }

    function test_EmitsProposalCreated() public {
        // emits the `ProposalCreated` event

        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 0,
            creator: alice,
            encryptedPayloadURI: "",
            destinationActionsHash: bytes32(0x1234000000000000000000000000000000000000000000000000000000000000)
        });
        eMultisig.createProposal(
            "", bytes32(0x1234000000000000000000000000000000000000000000000000000000000000), optimisticPlugin, true
        );

        // 2
        vm.startPrank(bob);

        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 1,
            creator: bob,
            encryptedPayloadURI: "ipfs://",
            destinationActionsHash: bytes32(0x0000567800000000000000000000000000000000000000000000000000000000)
        });
        eMultisig.createProposal(
            "ipfs://",
            bytes32(0x0000567800000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            false
        );
    }

    function test_RevertsIfSettingsChangedInSameBlock() public {
        // reverts if the stdMultisig settings have changed in the same block

        {
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: stdMultisig});

            eMultisig = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
        }

        // Same block
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, alice));
        eMultisig.createProposal("", bytes32(0), optimisticPlugin, false);

        // Next block
        vm.roll(block.number + 1);
        eMultisig.createProposal("", bytes32(0), optimisticPlugin, false);
    }

    function test_CreatesWhenUnlistedAccountsAllowed() public {
        // creates a proposal when unlisted accounts are allowed

        // Deploy a new instance with custom settings
        (dao, optimisticPlugin, stdMultisig, eMultisig,,) = builder.withoutOnlyListed().build();

        vm.startPrank(randomWallet);
        eMultisig.createProposal("", 0, optimisticPlugin, false);

        vm.startPrank(carol);
        eMultisig.createProposal("", 0, optimisticPlugin, false);

        vm.startPrank(david);
        eMultisig.createProposal("", 0, optimisticPlugin, false);
    }

    function test_RevertsWhenOnlyListedAndAnotherWalletCreates() public {
        // reverts if the user is not on the list and only listed accounts can create proposals

        vm.startPrank(randomWallet);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, randomWallet));
        eMultisig.createProposal("", 0, optimisticPlugin, false);

        vm.startPrank(taikoBridge);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, taikoBridge));
        eMultisig.createProposal("", 0, optimisticPlugin, false);
    }

    function test_RevertsWhenCreatorWasListedBeforeButNotNow() public {
        // reverts if `msg.sender` is not listed although she was listed in the last block

        dao.grant(address(stdMultisig), alice, stdMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // Remove
        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        stdMultisig.removeAddresses(addrs);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, alice));
        eMultisig.createProposal("", 0, optimisticPlugin, false);

        stdMultisig.addAddresses(addrs); // Add Alice back
        vm.roll(block.number + 1);
        eMultisig.createProposal("", 0, optimisticPlugin, false);

        // Add+remove
        addrs[0] = bob;
        stdMultisig.removeAddresses(addrs);

        vm.startPrank(bob);

        // Bob cannot create now
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, bob));
        eMultisig.createProposal("", 0, optimisticPlugin, false);

        vm.startPrank(alice);

        // Bob can create now
        stdMultisig.addAddresses(addrs); // Add Bob back

        vm.startPrank(alice);

        eMultisig.createProposal("", 0, optimisticPlugin, false);
    }

    function test_CreatesProposalWithoutApprovingIfUnspecified() public {
        // creates a proposal successfully and does not approve if not specified

        uint256 pid = eMultisig.createProposal(
            "",
            0,
            optimisticPlugin,
            false // approveProposal
        );

        assertEq(eMultisig.hasApproved(pid, alice), false, "Should not have approved");
        (, uint16 approvals,,,,) = eMultisig.getProposal(pid);
        assertEq(approvals, 0, "Should be 0");

        eMultisig.approve(pid);

        assertEq(eMultisig.hasApproved(pid, alice), true, "Should have approved");
        (, approvals,,,,) = eMultisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");
    }

    function test_CreatesAndApprovesWhenSpecified() public {
        // creates a proposal successfully and approves if specified

        vm.expectEmit();
        emit Approved({proposalId: 0, approver: alice});
        eMultisig.createProposal(
            "ipfs://",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            true
        );

        uint256 pid = eMultisig.createProposal(
            "ipfs://",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            true // approveProposal
        );
        assertEq(eMultisig.hasApproved(pid, alice), true, "Should have approved");
        (, uint16 approvals,,,,) = eMultisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");
    }

    function test_HashActionsReturnsProperData() public view {
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].to = address(dao);
        actions[0].value = 1 ether;
        actions[0].data = hex"00112233";

        bytes32 h1 = eMultisig.hashActions(actions);

        // 2
        actions[0].to = bob;
        bytes32 h2 = eMultisig.hashActions(actions);
        assertNotEq(h1, h2, "Hashes should differ");

        // 3
        actions[0].value = 2 ether;
        bytes32 h3 = eMultisig.hashActions(actions);
        assertNotEq(h2, h3, "Hashes should differ");

        // 4
        actions[0].data = hex"00112235";
        bytes32 h4 = eMultisig.hashActions(actions);
        assertNotEq(h3, h4, "Hashes should differ");

        // 5
        actions = new IDAO.Action[](0);
        bytes32 h5 = eMultisig.hashActions(actions);
        assertNotEq(h4, h5, "Hashes should differ");

        // 5'
        bytes32 h5b = eMultisig.hashActions(actions);
        assertEq(h5, h5b, "Hashes should match");
    }

    // CAN APPROVE

    function testFuzz_CanApproveReturnsfFalseIfNotCreated(uint256 randomProposalId) public view {
        // returns `false` if the proposal doesn't exist

        assertEq(eMultisig.canApprove(randomProposalId, alice), false, "Should be false");
        assertEq(eMultisig.canApprove(randomProposalId, bob), false, "Should be false");
        assertEq(eMultisig.canApprove(randomProposalId, carol), false, "Should be false");
        assertEq(eMultisig.canApprove(randomProposalId, david), false, "Should be false");
    }

    function testFuzz_CanApproveReturnsfFalseIfNotListed(address randomWallet) public {
        // returns `false` if the approver is not listed

        {
            // Leaving the deployment for fuzz efficiency

            // Deploy a new stdMultisig instance
            Multisig.MultisigSettings memory mSettings =
                Multisig.MultisigSettings({onlyListed: false, minApprovals: 1, destinationProposalDuration: 4 days});
            address[] memory signers = new address[](1);
            signers[0] = address(0x0);

            stdMultisig = Multisig(
                createProxyAndCall(
                    address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, mSettings))
                )
            );
            // New emergency stdMultisig using the above
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 1, addresslistSource: stdMultisig});
            eMultisig = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );

            vm.roll(block.number + 1);
        }

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        // ko
        if (randomWallet != address(0x0)) {
            assertEq(eMultisig.canApprove(pid, randomWallet), false, "Should be false");
        }

        // static ok
        assertEq(eMultisig.canApprove(pid, address(0)), true, "Should be true");
    }

    function test_CanApproveReturnsFalseIfApproved() public {
        // returns `false` if the approver has already approved
        builder = new DaoBuilder();
        (dao, optimisticPlugin, stdMultisig, eMultisig,,) = builder.withMultisigMember(alice).withMultisigMember(bob)
            .withMultisigMember(carol).withMultisigMember(david).withMinApprovals(4).build();

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        // Alice
        assertEq(eMultisig.canApprove(pid, alice), true, "Should be true");
        eMultisig.approve(pid);
        assertEq(eMultisig.canApprove(pid, alice), false, "Should be false");

        // Bob
        assertEq(eMultisig.canApprove(pid, bob), true, "Should be true");
        vm.startPrank(bob);
        eMultisig.approve(pid);
        assertEq(eMultisig.canApprove(pid, bob), false, "Should be false");

        // Carol
        assertEq(eMultisig.canApprove(pid, carol), true, "Should be true");
        vm.startPrank(carol);
        eMultisig.approve(pid);
        assertEq(eMultisig.canApprove(pid, carol), false, "Should be false");

        // David
        assertEq(eMultisig.canApprove(pid, david), true, "Should be true");
        vm.startPrank(david);
        eMultisig.approve(pid);
        assertEq(eMultisig.canApprove(pid, david), false, "Should be false");
    }

    function test_CanApproveReturnsFalseIfExpired() public {
        // returns `false` if the proposal has ended

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        assertEq(eMultisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1); // expiration time - 1
        assertEq(eMultisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(block.timestamp + 1); // expiration time
        assertEq(eMultisig.canApprove(pid, alice), false, "Should be false");

        // Start later
        vm.warp(50 days);
        pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        assertEq(eMultisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1); // expiration time - 1
        assertEq(eMultisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(block.timestamp + 1); // expiration time
        assertEq(eMultisig.canApprove(pid, alice), false, "Should be false");
    }

    function test_CanApproveReturnsFalseIfExecuted() public {
        // returns `false` if the proposal is already executed

        bool executed;
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);

        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);

        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid); // passed

        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        eMultisig.execute(pid, actions);

        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // David cannot approve
        assertEq(eMultisig.canApprove(pid, david), false, "Should be false");
    }

    function test_CanApproveReturnsTrueIfListed() public {
        // returns `true` if the approver is listed

        vm.warp(10);

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        assertEq(eMultisig.canApprove(pid, alice), true, "Should be true");
        assertEq(eMultisig.canApprove(pid, bob), true, "Should be true");
        assertEq(eMultisig.canApprove(pid, carol), true, "Should be true");
        assertEq(eMultisig.canApprove(pid, david), true, "Should be true");

        // new setup
        builder = new DaoBuilder();
        (dao, optimisticPlugin, stdMultisig, eMultisig,,) =
            builder.withMultisigMember(randomWallet).withMinApprovals(1).withMinDuration(0).build();

        // now ko
        vm.startPrank(randomWallet);
        pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        assertEq(eMultisig.canApprove(pid, alice), false, "Should be false");
        assertEq(eMultisig.canApprove(pid, bob), false, "Should be false");
        assertEq(eMultisig.canApprove(pid, carol), false, "Should be false");
        assertEq(eMultisig.canApprove(pid, david), false, "Should be false");

        // ok
        assertEq(eMultisig.canApprove(pid, randomWallet), true, "Should be true");
    }

    // HAS APPROVED

    function test_HasApprovedReturnsFalseWhenNotApproved() public {
        // returns `false` if user hasn't approved yet

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        // Alice
        assertEq(eMultisig.hasApproved(pid, alice), false, "Should be false");
        assertEq(eMultisig.hasApproved(pid, bob), false, "Should be false");
        assertEq(eMultisig.hasApproved(pid, carol), false, "Should be false");
        assertEq(eMultisig.hasApproved(pid, david), false, "Should be false");
    }

    function test_HasApprovedReturnsTrueWhenUserApproved() public {
        // returns `true` if user has approved

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        // Alice
        assertEq(eMultisig.hasApproved(pid, alice), false, "Should be false");
        eMultisig.approve(pid);
        assertEq(eMultisig.hasApproved(pid, alice), true, "Should be true");

        // Bob
        vm.startPrank(bob);
        assertEq(eMultisig.hasApproved(pid, bob), false, "Should be false");
        eMultisig.approve(pid);
        assertEq(eMultisig.hasApproved(pid, bob), true, "Should be true");

        // Carol
        vm.startPrank(carol);
        assertEq(eMultisig.hasApproved(pid, carol), false, "Should be false");
        eMultisig.approve(pid);
        assertEq(eMultisig.hasApproved(pid, carol), true, "Should be true");

        // David
        vm.startPrank(david);
        assertEq(eMultisig.hasApproved(pid, david), false, "Should be false");
        eMultisig.approve(pid);
        assertEq(eMultisig.hasApproved(pid, david), true, "Should be true");
    }

    // APPROVE

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

    function testFuzz_ApproveRevertsIfNotListed(address randomSigner) public {
        // Reverts if the signer is not listed

        builder = new DaoBuilder();
        (,,, eMultisig,,) = builder.withMultisigMember(alice).withMinApprovals(1).build();
        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        if (randomSigner == alice) {
            return;
        }

        vm.startPrank(randomSigner);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, randomSigner));
        eMultisig.approve(pid);
    }

    function test_ApproveRevertsIfAlreadyApproved() public {
        // reverts when approving multiple times

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        eMultisig.approve(pid);

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, bob));
        eMultisig.approve(pid);

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, carol));
        eMultisig.approve(pid);

        vm.startPrank(alice);
    }

    function test_ApprovesWithTheSenderAddress() public {
        // approves with the msg.sender address
        // Same as test_HasApprovedReturnsTrueWhenUserApproved()

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        // Alice
        assertEq(eMultisig.hasApproved(pid, alice), false, "Should be false");
        eMultisig.approve(pid);
        assertEq(eMultisig.hasApproved(pid, alice), true, "Should be true");

        // Bob
        vm.startPrank(bob);
        assertEq(eMultisig.hasApproved(pid, bob), false, "Should be false");
        eMultisig.approve(pid);
        assertEq(eMultisig.hasApproved(pid, bob), true, "Should be true");

        // Carol
        vm.startPrank(carol);
        assertEq(eMultisig.hasApproved(pid, carol), false, "Should be false");
        eMultisig.approve(pid);
        assertEq(eMultisig.hasApproved(pid, carol), true, "Should be true");

        // David
        vm.startPrank(david);
        assertEq(eMultisig.hasApproved(pid, david), false, "Should be false");
        eMultisig.approve(pid);
        assertEq(eMultisig.hasApproved(pid, david), true, "Should be true");

        vm.startPrank(alice);
    }

    function test_ApproveRevertsIfExpired() public {
        // reverts if the proposal has ended

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        assertEq(eMultisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        eMultisig.approve(pid);

        vm.warp(block.timestamp + 15 days);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        eMultisig.approve(pid);

        // 2
        vm.warp(10 days);
        pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        assertEq(eMultisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        eMultisig.approve(pid);

        vm.warp(block.timestamp + 15 days);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        eMultisig.approve(pid);
    }

    function test_ApproveRevertsIfExecuted() public {
        // reverts if the proposal has ended

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);
        eMultisig.approve(pid);
        vm.startPrank(bob);
        eMultisig.approve(pid);
        vm.startPrank(carol);
        eMultisig.approve(pid);

        eMultisig.execute(pid, actions);
        (bool executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, carol));
        eMultisig.approve(pid);
    }

    function test_ApprovingProposalsEmits() public {
        // Approving a proposal emits the Approved event

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        vm.expectEmit();
        emit Approved(pid, alice);
        eMultisig.approve(pid);

        // Bob
        vm.startPrank(bob);
        vm.expectEmit();
        emit Approved(pid, bob);
        eMultisig.approve(pid);

        // Carol
        vm.startPrank(carol);
        vm.expectEmit();
        emit Approved(pid, carol);
        eMultisig.approve(pid);

        // David (even if it already passed)
        vm.startPrank(david);
        vm.expectEmit();
        emit Approved(pid, david);
        eMultisig.approve(pid);
    }

    // CAN EXECUTE

    function testFuzz_CanExecuteReturnsFalseIfNotCreated(uint256 randomProposalId) public view {
        // returns `false` if the proposal doesn't exist

        assertEq(eMultisig.canExecute(randomProposalId), false, "Should be false");
    }

    function test_CanExecuteReturnsFalseIfBelowMinApprovals() public {
        // returns `false` if the proposal has not reached the minimum approvals yet

        (dao, optimisticPlugin, stdMultisig, eMultisig,,) = builder.withMinApprovals(2).build();

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), false, "Should be false");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), true, "Should be true");

        vm.startPrank(alice);

        // More approvals required (4)
        (dao, optimisticPlugin, stdMultisig, eMultisig,,) = builder.withMinApprovals(4).build();

        pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), false, "Should be false");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), false, "Should be false");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), false, "Should be false");

        // David
        vm.startPrank(david);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), true, "Should be true");
    }

    function test_CanExecuteReturnsFalseIfExpired() public {
        // returns `false` if the proposal has expired

        // 1
        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        eMultisig.approve(pid);
        vm.startPrank(bob);
        eMultisig.approve(pid);
        vm.startPrank(carol);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1);
        assertEq(eMultisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + 1);
        assertEq(eMultisig.canExecute(pid), false, "Should be false");

        // 2
        vm.warp(50 days);

        pid = eMultisig.createProposal("", 0, optimisticPlugin, false);

        vm.startPrank(alice);
        eMultisig.approve(pid);
        vm.startPrank(bob);
        eMultisig.approve(pid);
        vm.startPrank(carol);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1);
        assertEq(eMultisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + 1);
        assertEq(eMultisig.canExecute(pid), false, "Should be false");
    }

    function test_CanExecuteReturnsFalseIfExecuted() public {
        // returns `false` if the proposal is already executed

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);

        assertEq(eMultisig.canExecute(pid), true, "Should be true");
        eMultisig.execute(pid, actions);

        assertEq(eMultisig.canExecute(pid), false, "Should be false");
    }

    function test_CanExecuteReturnsTrueWhenAllGood() public {
        // returns `true` if the proposal can be executed

        uint256 pid = eMultisig.createProposal("", 0, optimisticPlugin, false);
        assertEq(eMultisig.canExecute(pid), false, "Should be false");

        // Alice
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), false, "Should be false");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), false, "Should be false");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);

        assertEq(eMultisig.canExecute(pid), true, "Should be true");
    }

    // EXECUTE

    function testFuzz_ExecuteRevertsIfNotCreated(uint256 randomProposalId) public {
        // reverts if the proposal doesn't exist

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, randomProposalId));
        eMultisig.execute(randomProposalId, actions);
    }

    function test_ExecuteRevertsIfBelowMinApprovals() public {
        // reverts if minApprovals is not met yet

        (dao, optimisticPlugin, stdMultisig, eMultisig,,) = builder.withMinApprovals(2).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        eMultisig.execute(pid, actions);

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        eMultisig.execute(pid, actions); // ok

        vm.startPrank(alice);

        // More approvals required (4)
        (dao, optimisticPlugin, stdMultisig, eMultisig,,) = builder.withMinApprovals(4).build();

        pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        eMultisig.approve(pid);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        eMultisig.execute(pid, actions);

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        eMultisig.execute(pid, actions);

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        eMultisig.execute(pid, actions);

        // David
        vm.startPrank(david);
        eMultisig.approve(pid);
        eMultisig.execute(pid, actions);
    }

    function test_ExecuteRevertsIfExpired() public {
        // reverts if the proposal has expired

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        eMultisig.approve(pid);
        vm.startPrank(bob);
        eMultisig.approve(pid);
        vm.startPrank(carol);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        eMultisig.execute(pid, actions);

        vm.warp(100 days);

        // 2
        pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        vm.startPrank(alice);
        eMultisig.approve(pid);
        vm.startPrank(bob);
        eMultisig.approve(pid);
        vm.startPrank(carol);
        eMultisig.approve(pid);
        assertEq(eMultisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        eMultisig.execute(pid, actions);
    }

    function test_ExecuteRevertsWhenAlreadyExecuted() public {
        // executes if the minimum approval is met when stdMultisig with the `tryExecution` option

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);

        assertEq(eMultisig.canExecute(pid), true, "Should be true");
        eMultisig.execute(pid, actions);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        eMultisig.execute(pid, actions);
    }

    function test_ExecuteEmitsEvents() public {
        // emits the `ProposalExecuted` and `ProposalCreated` events

        vm.warp(5 days);
        vm.deal(address(dao), 1 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);

        // event
        vm.expectEmit();
        emit Executed(pid);
        vm.expectEmit();
        uint256 targetPid = 5 days << 128 | 5 days << 64;
        emit ProposalCreated(targetPid, address(eMultisig), 5 days, 5 days, "", actions, 0);
        eMultisig.execute(pid, actions);

        // 2
        vm.warp(20 days);
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        actionsHash = eMultisig.hashActions(actions);
        pid = eMultisig.createProposal("ipfs://", actionsHash, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        eMultisig.approve(pid);

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);

        // events
        vm.expectEmit();
        emit Executed(pid);
        vm.expectEmit();
        targetPid = (20 days << 128 | 20 days << 64) + 1;
        emit ProposalCreated(targetPid, address(eMultisig), 20 days, 20 days, "ipfs://", actions, 0);
        eMultisig.execute(pid, actions);
    }

    function test_ExecutesWithEnoughApprovalsOnTime() public {
        // executes if the minimum approval is met

        vm.deal(address(dao), 1 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);
        (bool executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        eMultisig.execute(pid, actions);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // 2
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";

        actionsHash = eMultisig.hashActions(actions);
        pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        eMultisig.execute(pid, actions);

        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");
    }

    function test_ExecuteRevertsWhenTheGivenActionsDontMatchTheHash() public {
        vm.deal(address(dao), 1 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = 0; // invalid hash
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);
        (bool executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.InvalidActions.selector, pid));
        eMultisig.execute(pid, actions);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // 2
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";

        actionsHash = eMultisig.hashActions(actions);
        pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Fake actions
        IDAO.Action[] memory otherActions = new IDAO.Action[](1);
        otherActions[0].value = 10000 ether;
        otherActions[0].to = address(carol);
        otherActions[0].data = hex"44556677";
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.InvalidActions.selector, pid));
        eMultisig.execute(pid, otherActions);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // With ok actions
        eMultisig.execute(pid, actions);

        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");
    }

    function test_ExecuteWhenPassedAndCalledByAnyoneWithTheActions() public {
        // executes if the minimum approval is met and can be called by an unlisted accounts

        vm.deal(address(dao), 4 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);
        (bool executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        vm.startPrank(randomWallet);
        eMultisig.execute(pid, actions);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // 2
        vm.startPrank(alice);

        actions = new IDAO.Action[](1);
        actions[0].value = 3 ether;
        actions[0].to = address(carol);
        actions[0].data = hex"0011223344556677";
        actionsHash = eMultisig.hashActions(actions);
        pid = eMultisig.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        eMultisig.approve(pid);
        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        vm.startPrank(randomWallet);
        eMultisig.execute(pid, actions);

        (executed,,,,,) = eMultisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");
    }

    function test_GetProposalReturnsTheRightValues() public {
        // Get proposal returns the right values

        vm.warp(10);
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        bytes32 actionsHash = eMultisig.hashActions(actions);
        uint256 pid = eMultisig.createProposal("ipfs://", actionsHash, optimisticPlugin, false);

        (
            bool executed,
            uint16 approvals,
            EmergencyMultisig.ProposalParameters memory parameters,
            bytes memory encryptedPayloadURI,
            bytes32 destinationActionsHash,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = eMultisig.getProposal(pid);

        assertEq(executed, false);
        assertEq(approvals, 0);
        assertEq(parameters.minApprovals, 3);
        assertEq(parameters.snapshotBlock, block.number - 1);
        assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(encryptedPayloadURI, "ipfs://");
        assertEq(destinationActionsHash, actionsHash);
        assertEq(address(destinationPlugin), address(optimisticPlugin));

        // 2 new
        OptimisticTokenVotingPlugin newOptimisticPlugin;
        (dao, newOptimisticPlugin, stdMultisig, eMultisig,,) = builder.build();
        vm.deal(address(dao), 1 ether);

        pid = eMultisig.createProposal("ipfs://12340000", actionsHash, newOptimisticPlugin, true);

        (executed, approvals, parameters, encryptedPayloadURI, destinationActionsHash, destinationPlugin) =
            eMultisig.getProposal(pid);

        assertEq(executed, false);
        assertEq(approvals, 1);
        assertEq(parameters.minApprovals, 3);
        assertEq(parameters.snapshotBlock, block.number - 1);
        assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(encryptedPayloadURI, "ipfs://12340000");
        assertEq(destinationActionsHash, actionsHash);
        assertEq(address(destinationPlugin), address(newOptimisticPlugin));

        // 3 approve
        vm.startPrank(bob);
        eMultisig.approve(pid);
        vm.startPrank(carol);
        eMultisig.approve(pid);

        (executed, approvals, parameters, encryptedPayloadURI, destinationActionsHash, destinationPlugin) =
            eMultisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 3);
        assertEq(parameters.snapshotBlock, block.number - 1);
        assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(encryptedPayloadURI, "ipfs://12340000");
        assertEq(destinationActionsHash, actionsHash);
        assertEq(address(destinationPlugin), address(newOptimisticPlugin));

        // Execute
        vm.startPrank(alice);
        dao.grant(address(newOptimisticPlugin), address(eMultisig), newOptimisticPlugin.PROPOSER_PERMISSION_ID());
        eMultisig.execute(pid, actions);

        // 4 execute
        (executed, approvals, parameters, encryptedPayloadURI, destinationActionsHash, destinationPlugin) =
            eMultisig.getProposal(pid);

        assertEq(executed, true, "Should be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 3);
        assertEq(parameters.snapshotBlock, block.number - 1);
        assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(encryptedPayloadURI, "ipfs://12340000");
        assertEq(destinationActionsHash, actionsHash);
        assertEq(address(destinationPlugin), address(newOptimisticPlugin));
    }

    function testFuzz_GetProposalReturnsEmptyValuesForNonExistingOnes(uint256 randomProposalId) public view {
        (
            bool executed,
            uint16 approvals,
            EmergencyMultisig.ProposalParameters memory parameters,
            bytes memory encryptedPayloadURI,
            bytes32 destinationActionsHash,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = eMultisig.getProposal(randomProposalId);

        assertEq(executed, false, "The proposal should not be executed");
        assertEq(approvals, 0, "The tally should be zero");
        assertEq(encryptedPayloadURI, "", "Incorrect encryptedPayloadURI");
        assertEq(parameters.expirationDate, 0, "Incorrect expirationDate");
        assertEq(parameters.snapshotBlock, 0, "Incorrect snapshotBlock");
        assertEq(parameters.minApprovals, 0, "Incorrect minApprovals");
        assertEq(destinationActionsHash, 0, "Actions hash should have no items");
        assertEq(address(destinationPlugin), address(0), "Incorrect destination plugin");
    }

    function test_ProxiedProposalHasTheSameSettingsAsTheOriginal() public {
        // Recreated proposal has the same settings and actions as registered here

        bool open;
        bool executed;
        OptimisticTokenVotingPlugin.ProposalParameters memory parameters;
        uint256 vetoTally;
        bytes memory metadataUri;
        IDAO.Action[] memory retrievedActions;
        uint256 allowFailureMap;

        vm.warp(10 days);
        vm.deal(address(dao), 100 ether);

        IDAO.Action[] memory submittedActions = new IDAO.Action[](3);
        submittedActions[0].to = alice;
        submittedActions[0].value = 1 ether;
        submittedActions[0].data = hex"";
        submittedActions[1].to = bob;
        submittedActions[1].value = 2 ether;
        submittedActions[1].data = hex"";
        submittedActions[2].to = carol;
        submittedActions[2].value = 3 ether;
        submittedActions[2].data = hex"";
        uint256 pid = eMultisig.createProposal(
            "ipfs://metadata", eMultisig.hashActions(submittedActions), optimisticPlugin, false
        );

        // Approve
        eMultisig.approve(pid);
        vm.startPrank(bob);
        eMultisig.approve(pid);
        vm.startPrank(carol);
        eMultisig.approve(pid);

        vm.startPrank(alice);
        eMultisig.execute(pid, submittedActions);

        // Check round
        (open, executed, parameters, vetoTally, metadataUri, retrievedActions, allowFailureMap) =
            optimisticPlugin.getProposal((uint256(block.timestamp) << 128 | uint256(block.timestamp) << 64));

        assertEq(open, false, "Should not be open");
        assertEq(executed, true, "Should be executed");
        assertEq(vetoTally, 0, "Should be 0");

        assertEq(parameters.vetoEndDate, block.timestamp, "Incorrect vetoEndDate");
        assertEq(metadataUri, "ipfs://metadata", "Incorrect target metadataUri");

        assertEq(retrievedActions.length, 3, "Should be 3");

        assertEq(retrievedActions[0].to, alice, "Incorrect to");
        assertEq(retrievedActions[0].value, 1 ether, "Incorrect value");
        assertEq(retrievedActions[0].data, hex"", "Incorrect data");
        assertEq(retrievedActions[1].to, bob, "Incorrect to");
        assertEq(retrievedActions[1].value, 2 ether, "Incorrect value");
        assertEq(retrievedActions[1].data, hex"", "Incorrect data");
        assertEq(retrievedActions[2].to, carol, "Incorrect to");
        assertEq(retrievedActions[2].value, 3 ether, "Incorrect value");
        assertEq(retrievedActions[2].data, hex"", "Incorrect data");

        assertEq(allowFailureMap, 0, "Should be 0");

        // New proposal
        vm.warp(15 days);

        submittedActions = new IDAO.Action[](2);
        submittedActions[1].to = address(dao);
        submittedActions[1].value = 0;
        submittedActions[1].data = abi.encodeWithSelector(DAO.daoURI.selector);
        submittedActions[0].to = address(stdMultisig);
        submittedActions[0].value = 0;
        submittedActions[0].data = abi.encodeWithSelector(Addresslist.addresslistLength.selector);
        pid = eMultisig.createProposal(
            "ipfs://more-metadata", eMultisig.hashActions(submittedActions), optimisticPlugin, false
        );

        // Approve
        eMultisig.approve(pid);
        vm.startPrank(bob);
        eMultisig.approve(pid);
        vm.startPrank(carol);
        eMultisig.approve(pid);

        vm.startPrank(alice);
        eMultisig.execute(pid, submittedActions);

        // Check round
        (open, executed, parameters, vetoTally, metadataUri, retrievedActions, allowFailureMap) =
            optimisticPlugin.getProposal((uint256(block.timestamp) << 128 | uint256(block.timestamp) << 64) + 1);

        assertEq(open, false, "Should not be open");
        assertEq(executed, true, "Should be executed");
        assertEq(vetoTally, 0, "Should be 0");

        assertEq(parameters.vetoEndDate, 15 days, "Incorrect vetoEndDate");
        assertEq(metadataUri, "ipfs://more-metadata", "Incorrect target metadataUri");

        assertEq(retrievedActions.length, 2, "Should be 2");

        assertEq(retrievedActions[1].to, address(dao), "Incorrect to");
        assertEq(retrievedActions[1].value, 0, "Incorrect value");
        assertEq(retrievedActions[1].data, abi.encodeWithSelector(DAO.daoURI.selector), "Incorrect data");
        assertEq(retrievedActions[0].to, address(stdMultisig), "Incorrect to");
        assertEq(retrievedActions[0].value, 0, "Incorrect value");
        assertEq(
            retrievedActions[0].data, abi.encodeWithSelector(Addresslist.addresslistLength.selector), "Incorrect data"
        );

        assertEq(allowFailureMap, 0, "Should be 0");
    }

    // Upgrade eMultisig

    function test_UpgradeToRevertsWhenCalledFromNonUpgrader() public {
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
    }

    function test_UpgradeToAndCallRevertsWhenCalledFromNonUpgrader() public {
        address initialImplementation = eMultisig.implementation();
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        address _newImplementation = address(new EmergencyMultisig());

        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: stdMultisig});

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
    }

    function test_UpgradeToSucceedsWhenCalledFromUpgrader() public {
        dao.grant(address(eMultisig), alice, eMultisig.UPGRADE_PLUGIN_PERMISSION_ID());

        address _newImplementation = address(new EmergencyMultisig());

        vm.expectEmit();
        emit Upgraded(_newImplementation);

        eMultisig.upgradeTo(_newImplementation);

        assertEq(eMultisig.implementation(), address(_newImplementation));
    }

    function test_UpgradeToAndCallSucceedsWhenCalledFromUpgrader() public {
        dao.grant(address(eMultisig), alice, eMultisig.UPGRADE_PLUGIN_PERMISSION_ID());
        dao.grant(address(eMultisig), alice, eMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        address _newImplementation = address(new EmergencyMultisig());

        vm.expectEmit();
        emit Upgraded(_newImplementation);

        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: stdMultisig});
        eMultisig.upgradeToAndCall(
            _newImplementation, abi.encodeCall(EmergencyMultisig.updateMultisigSettings, (settings))
        );

        assertEq(eMultisig.implementation(), address(_newImplementation));
    }
}
