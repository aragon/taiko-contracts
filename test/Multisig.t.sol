// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {StandardProposalCondition} from "../src/conditions/StandardProposalCondition.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {Multisig} from "../src/Multisig.sol";
import {IMultisig} from "../src/interfaces/IMultisig.sol";
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

contract MultisigTest is AragonTest {
    DaoBuilder builder;

    DAO dao;
    Multisig multisig;
    OptimisticTokenVotingPlugin optimisticPlugin;

    // Events/errors to be tested here (duplicate)
    event MultisigSettingsUpdated(bool onlyListed, uint16 indexed minApprovals, uint64 destinationProposalDuration);
    event MembersAdded(address[] members);
    event MembersRemoved(address[] members);

    error InvalidAddresslistUpdate(address member);

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
        (dao, optimisticPlugin, multisig,,,) = builder.withMultisigMember(alice).withMultisigMember(bob)
            .withMultisigMember(carol).withMultisigMember(david).withMinApprovals(3).build();
    }

    function test_RevertsIfTryingToReinitialize() public {
        // Deploy a new multisig instance
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 3, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        // Reinitialize should fail
        vm.expectRevert("Initializable: contract is already initialized");
        multisig.initialize(dao, signers, settings);
    }

    function test_InitializeAddsInitialAddresses() public {
        // Deploy with 4 signers
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 3, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        assertEq(multisig.isListed(alice), true, "Should be a member");
        assertEq(multisig.isListed(bob), true, "Should be a member");
        assertEq(multisig.isListed(carol), true, "Should be a member");
        assertEq(multisig.isListed(david), true, "Should be a member");
        assertEq(multisig.isListed(randomWallet), false, "Should not be a member");

        // Redeploy with just 2 signers
        builder = new DaoBuilder();
        (dao, optimisticPlugin, multisig,,,) = builder.withMultisigMember(alice).withMultisigMember(bob).build();

        assertEq(multisig.isListed(alice), true, "Should be a member");
        assertEq(multisig.isListed(bob), true, "Should be a member");
        assertEq(multisig.isListed(carol), false, "Should not be a member");
        assertEq(multisig.isListed(david), false, "Should not be a member");
        assertEq(multisig.isListed(randomWallet), false, "Should not be a member");

        // Redeploy with 5 signers
        builder = new DaoBuilder();
        (dao, optimisticPlugin, multisig,,,) = builder.withMultisigMember(alice).withMultisigMember(bob)
            .withMultisigMember(carol).withMultisigMember(david).withMultisigMember(randomWallet).build();

        assertEq(multisig.isListed(alice), true, "Should be a member");
        assertEq(multisig.isListed(bob), true, "Should be a member");
        assertEq(multisig.isListed(carol), true, "Should be a member");
        assertEq(multisig.isListed(david), true, "Should be a member");
        assertEq(multisig.isListed(randomWallet), true, "Should be a member");
    }

    function test_InitializeSetsMinApprovals() public {
        // 2
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 2, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        (, uint16 minApprovals,) = multisig.multisigSettings();
        assertEq(minApprovals, uint16(2), "Incorrect minApprovals");

        // Redeploy with 1
        settings.minApprovals = 1;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        (, minApprovals,) = multisig.multisigSettings();
        assertEq(minApprovals, uint16(1), "Incorrect minApprovals");
    }

    function test_InitializeSetsOnlyListed() public {
        // Deploy with true
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 3, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        (bool onlyListed,,) = multisig.multisigSettings();
        assertEq(onlyListed, true, "Incorrect onlyListed");

        // Redeploy with false
        settings.onlyListed = false;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        (onlyListed,,) = multisig.multisigSettings();
        assertEq(onlyListed, false, "Incorrect onlyListed");
    }

    function test_InitializeSetsDestinationProposalDuration() public {
        // Deploy with 5 days
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 3, destinationProposalDuration: 5 days});
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        (,, uint64 minDuration) = multisig.multisigSettings();
        assertEq(minDuration, 5 days, "Incorrect minDuration");

        // Redeploy with 3 days
        settings.destinationProposalDuration = 3 days;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        (,, minDuration) = multisig.multisigSettings();
        assertEq(minDuration, 3 days, "Incorrect minDuration");
    }

    function test_InitializeEmitsMultisigSettingsUpdatedOnInstall() public {
        // Deploy with true/3/2
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 3, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, uint16(3), 4 days);

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        // Deploy with false/2/7
        settings = Multisig.MultisigSettings({onlyListed: false, minApprovals: 2, destinationProposalDuration: 7 days});
        vm.expectEmit();
        emit MultisigSettingsUpdated(false, uint16(2), 7 days);

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );
    }

    function test_InitializeRevertsIfMembersListIsTooLong() public {
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 3, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](65537);

        vm.expectRevert(abi.encodeWithSelector(Multisig.AddresslistLengthOutOfBounds.selector, 65535, 65537));
        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );
    }

    // INTERFACES

    function test_DoesntSupportTheEmptyInterface() public view {
        bool supported = multisig.supportsInterface(0);
        assertEq(supported, false, "Should not support the empty interface");
    }

    function test_SupportsIERC165Upgradeable() public view {
        bool supported = multisig.supportsInterface(type(IERC165Upgradeable).interfaceId);
        assertEq(supported, true, "Should support IERC165Upgradeable");
    }

    function test_SupportsIPlugin() public view {
        bool supported = multisig.supportsInterface(type(IPlugin).interfaceId);
        assertEq(supported, true, "Should support IPlugin");
    }

    function test_SupportsIProposal() public view {
        bool supported = multisig.supportsInterface(type(IProposal).interfaceId);
        assertEq(supported, true, "Should support IProposal");
    }

    function test_SupportsIMembership() public view {
        bool supported = multisig.supportsInterface(type(IMembership).interfaceId);
        assertEq(supported, true, "Should support IMembership");
    }

    function test_SupportsAddresslist() public view {
        bool supported = multisig.supportsInterface(type(Addresslist).interfaceId);
        assertEq(supported, true, "Should support Addresslist");
    }

    function test_SupportsIMultisig() public view {
        bool supported = multisig.supportsInterface(type(IMultisig).interfaceId);
        assertEq(supported, true, "Should support IMultisig");
    }

    // UPDATE MULTISIG SETTINGS

    function test_ShouldntAllowMinApprovalsHigherThenAddrListLength() public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5,
            destinationProposalDuration: 4 days // Greater than 4 members below
        });
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 4, 5));

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        // Retry with onlyListed false
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 6,
            destinationProposalDuration: 4 days // Greater than 4 members below
        });
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 4, 6));
        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );
    }

    function test_ShouldNotAllowMinApprovalsZero() public {
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 0, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        // Retry with onlyListed false
        settings = Multisig.MultisigSettings({onlyListed: false, minApprovals: 0, destinationProposalDuration: 4 days});
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );
    }

    function test_EmitsMultisigSettingsUpdated() public {
        dao.grant(address(multisig), address(alice), multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // 1
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 1, 4 days);
        multisig.updateMultisigSettings(settings);

        // 2
        settings = Multisig.MultisigSettings({onlyListed: true, minApprovals: 2, destinationProposalDuration: 5 days});

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 2, 5 days);
        multisig.updateMultisigSettings(settings);

        // 3
        settings = Multisig.MultisigSettings({onlyListed: false, minApprovals: 3, destinationProposalDuration: 0});

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 3, 0);
        multisig.updateMultisigSettings(settings);

        // 4
        settings = Multisig.MultisigSettings({onlyListed: false, minApprovals: 4, destinationProposalDuration: 1 days});

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 4, 1 days);
        multisig.updateMultisigSettings(settings);
    }

    function test_onlyWalletWithPermissionsCanUpdateSettings() public {
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 3 days});
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

        // Retry with the permission
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 1, 3 days);
        multisig.updateMultisigSettings(settings);
    }

    function test_IsMemberShouldReturnWhenApropriate() public {
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](1);
        signers[0] = alice;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        assertEq(multisig.isMember(alice), true, "Should be a member");
        assertEq(multisig.isMember(bob), false, "Should not be a member");
        assertEq(multisig.isMember(carol), false, "Should not be a member");
        assertEq(multisig.isMember(david), false, "Should not be a member");

        // More members
        settings = Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        signers = new address[](3);
        signers[0] = bob;
        signers[1] = carol;
        signers[2] = david;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        assertEq(multisig.isMember(alice), false, "Should not be a member");
        assertEq(multisig.isMember(bob), true, "Should be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");
    }

    function test_IsMemberIsListedShouldReturnTheSameValue() public {
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](1);
        signers[0] = alice;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        assertEq(multisig.isListed(alice), multisig.isMember(alice), "isMember isListed should be equal");
        assertEq(multisig.isListed(bob), multisig.isMember(bob), "isMember isListed should be equal");
        assertEq(multisig.isListed(carol), multisig.isMember(carol), "isMember isListed should be equal");
        assertEq(multisig.isListed(david), multisig.isMember(david), "isMember isListed should be equal");

        // More members
        settings = Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        signers = new address[](3);
        signers[0] = bob;
        signers[1] = carol;
        signers[2] = david;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        assertEq(multisig.isListed(alice), multisig.isMember(alice), "isMember isListed should be equal");
        assertEq(multisig.isListed(bob), multisig.isMember(bob), "isMember isListed should be equal");
        assertEq(multisig.isListed(carol), multisig.isMember(carol), "isMember isListed should be equal");
        assertEq(multisig.isListed(david), multisig.isMember(david), "isMember isListed should be equal");
    }

    function testFuzz_IsMemberIsFalseByDefault(uint256 _randomEntropy) public {
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](1); // 0x0... would be a member but the chance is negligible

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        assertEq(multisig.isListed(randomWallet), false, "Should be false");
        assertEq(
            multisig.isListed(vm.addr(uint256(keccak256(abi.encodePacked(_randomEntropy))))), false, "Should be false"
        );
    }

    function test_AddsNewMembersAndEmits() public {
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // No
        assertEq(multisig.isMember(randomWallet), false, "Should not be a member");

        address[] memory addrs = new address[](1);
        addrs[0] = randomWallet;

        vm.expectEmit();
        emit MembersAdded({members: addrs});
        multisig.addAddresses(addrs);

        // Yes
        assertEq(multisig.isMember(randomWallet), true, "Should be a member");

        // Next
        addrs = new address[](3);
        addrs[0] = vm.addr(1234);
        addrs[1] = vm.addr(2345);
        addrs[2] = vm.addr(3456);

        // No
        assertEq(multisig.isMember(addrs[0]), false, "Should not be a member");
        assertEq(multisig.isMember(addrs[1]), false, "Should not be a member");
        assertEq(multisig.isMember(addrs[2]), false, "Should not be a member");

        vm.expectEmit();
        emit MembersAdded({members: addrs});
        multisig.addAddresses(addrs);

        // Yes
        assertEq(multisig.isMember(addrs[0]), true, "Should be a member");
        assertEq(multisig.isMember(addrs[1]), true, "Should be a member");
        assertEq(multisig.isMember(addrs[2]), true, "Should be a member");
    }

    function test_RemovesMembersAndEmits() public {
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        multisig.updateMultisigSettings(settings);

        // Before
        assertEq(multisig.isMember(alice), true, "Should be a member");
        assertEq(multisig.isMember(bob), true, "Should be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;

        vm.expectEmit();
        emit MembersRemoved({members: addrs});
        multisig.removeAddresses(addrs);

        // After
        assertEq(multisig.isMember(alice), false, "Should not be a member");
        assertEq(multisig.isMember(bob), false, "Should not be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        // Next
        addrs = new address[](3);
        addrs[0] = vm.addr(1234);
        addrs[1] = vm.addr(2345);
        addrs[2] = vm.addr(3456);
        multisig.addAddresses(addrs);

        // Remove
        addrs = new address[](2);
        addrs[0] = carol;
        addrs[1] = david;

        vm.expectEmit();
        emit MembersRemoved({members: addrs});
        multisig.removeAddresses(addrs);

        // Yes
        assertEq(multisig.isMember(carol), false, "Should not be a member");
        assertEq(multisig.isMember(david), false, "Should not be a member");
    }

    function test_ShouldRevertIfEmptySignersList() public {
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        multisig.updateMultisigSettings(settings);

        // Before
        assertEq(multisig.isMember(alice), true, "Should be a member");
        assertEq(multisig.isMember(bob), true, "Should be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        // ok
        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        multisig.removeAddresses(addrs);

        addrs[0] = bob;
        multisig.removeAddresses(addrs);

        addrs[0] = carol;
        multisig.removeAddresses(addrs);

        assertEq(multisig.isMember(alice), false, "Should not be a member");
        assertEq(multisig.isMember(bob), false, "Should not be a member");
        assertEq(multisig.isMember(carol), false, "Should not be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        // ko
        addrs[0] = david;
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        multisig.removeAddresses(addrs);

        // Next
        addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        multisig.addAddresses(addrs);

        // Retry removing David
        addrs = new address[](1);
        addrs[0] = david;

        multisig.removeAddresses(addrs);

        // Yes
        assertEq(multisig.isMember(david), false, "Should not be a member");
    }

    function test_ShouldRevertIfLessThanMinApproval() public {
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // Before
        assertEq(multisig.isMember(alice), true, "Should be a member");
        assertEq(multisig.isMember(bob), true, "Should be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        // ok
        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        multisig.removeAddresses(addrs);

        // ko
        addrs[0] = bob;
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 3, 2));
        multisig.removeAddresses(addrs);

        // ko
        addrs[0] = carol;
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 3, 2));
        multisig.removeAddresses(addrs);

        // ko
        addrs[0] = david;
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 3, 2));
        multisig.removeAddresses(addrs);

        // Add and retry removing

        addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        multisig.addAddresses(addrs);

        addrs = new address[](1);
        addrs[0] = bob;
        multisig.removeAddresses(addrs);

        // 2
        addrs = new address[](1);
        addrs[0] = vm.addr(2345);
        multisig.addAddresses(addrs);

        addrs = new address[](1);
        addrs[0] = carol;
        multisig.removeAddresses(addrs);

        // 3
        addrs = new address[](1);
        addrs[0] = vm.addr(3456);
        multisig.addAddresses(addrs);

        addrs = new address[](1);
        addrs[0] = david;
        multisig.removeAddresses(addrs);
    }

    function test_MinApprovalsBiggerThanTheListReverts() public {
        // MinApprovals should be within the boundaries of the list
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5,
            destinationProposalDuration: 4 days // More than 4
        });
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 4, 5));
        multisig.updateMultisigSettings(settings);

        // More signers

        address[] memory signers = new address[](1);
        signers[0] = randomWallet;
        multisig.addAddresses(signers);

        // should not fail now
        multisig.updateMultisigSettings(settings);

        // More than that, should fail again
        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 6,
            destinationProposalDuration: 4 days // More than 5
        });
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 5, 6));
        multisig.updateMultisigSettings(settings);
    }

    function test_ShouldRevertIfDuplicatingAddresses() public {
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // ok
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        multisig.addAddresses(addrs);

        // ko
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.addAddresses(addrs);

        // 1
        addrs[0] = alice;
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.addAddresses(addrs);

        // 2
        addrs[0] = bob;
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.addAddresses(addrs);

        // 3
        addrs[0] = carol;
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.addAddresses(addrs);

        // 4
        addrs[0] = david;
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.addAddresses(addrs);

        // ok
        addrs[0] = vm.addr(1234);
        multisig.removeAddresses(addrs);

        // ko
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.removeAddresses(addrs);

        addrs[0] = vm.addr(2345);
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.removeAddresses(addrs);

        addrs[0] = vm.addr(3456);
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.removeAddresses(addrs);

        addrs[0] = vm.addr(4567);
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.removeAddresses(addrs);

        addrs[0] = randomWallet;
        vm.expectRevert(abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0]));
        multisig.removeAddresses(addrs);
    }

    function test_onlyWalletWithPermissionsCanAddRemove() public {
        // ko
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(multisig),
                alice,
                multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
            )
        );
        multisig.addAddresses(addrs);

        // ko
        addrs[0] = alice;
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(multisig),
                alice,
                multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
            )
        );
        multisig.removeAddresses(addrs);

        // Permission
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // ok
        addrs[0] = vm.addr(1234);
        multisig.addAddresses(addrs);

        addrs[0] = alice;
        multisig.removeAddresses(addrs);
    }

    function testFuzz_PermissionedAddRemoveMembers(address randomAccount) public {
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        assertEq(multisig.isMember(randomWallet), false, "Should be false");

        // in
        address[] memory addrs = new address[](1);
        addrs[0] = randomWallet;
        multisig.addAddresses(addrs);
        assertEq(multisig.isMember(randomWallet), true, "Should be true");

        // out
        multisig.removeAddresses(addrs);
        assertEq(multisig.isMember(randomWallet), false, "Should be false");

        // someone else
        if (randomAccount != alice) {
            vm.startPrank(randomAccount);
            vm.expectRevert(
                abi.encodeWithSelector(
                    DaoUnauthorized.selector,
                    address(dao),
                    address(multisig),
                    randomAccount,
                    multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
                )
            );
            multisig.addAddresses(addrs);
            assertEq(multisig.isMember(randomWallet), false, "Should be false");

            addrs[0] = carol;
            assertEq(multisig.isMember(carol), true, "Should be true");
            vm.expectRevert(
                abi.encodeWithSelector(
                    DaoUnauthorized.selector,
                    address(dao),
                    address(multisig),
                    randomAccount,
                    multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
                )
            );
            multisig.removeAddresses(addrs);

            assertEq(multisig.isMember(carol), true, "Should be true");
        }

        vm.startPrank(alice);
    }

    function testFuzz_PermissionedUpdateSettings(address randomAccount) public {
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        (bool onlyListed, uint16 minApprovals, uint64 destMinDuration) = multisig.multisigSettings();
        assertEq(minApprovals, 3, "Should be 3");
        assertEq(onlyListed, true, "Should be true");
        assertEq(destMinDuration, 10 days, "Incorrect destMinDuration A");

        // in
        Multisig.MultisigSettings memory newSettings =
            Multisig.MultisigSettings({onlyListed: false, minApprovals: 2, destinationProposalDuration: 5 days});
        multisig.updateMultisigSettings(newSettings);

        (onlyListed, minApprovals, destMinDuration) = multisig.multisigSettings();
        assertEq(minApprovals, 2, "Should be 2");
        assertEq(onlyListed, false, "Should be false");
        assertEq(destMinDuration, 5 days, "Incorrect destMinDuration B");

        // out
        newSettings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 6 days});
        multisig.updateMultisigSettings(newSettings);
        (onlyListed, minApprovals, destMinDuration) = multisig.multisigSettings();
        assertEq(minApprovals, 1, "Should be 1");
        assertEq(onlyListed, true, "Should be true");
        assertEq(destMinDuration, 6 days, "Incorrect destMinDuration C");

        vm.roll(block.number + 1);

        // someone else
        if (randomAccount != alice) {
            vm.startPrank(randomAccount);

            newSettings =
                Multisig.MultisigSettings({onlyListed: false, minApprovals: 4, destinationProposalDuration: 4 days});

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

            (onlyListed, minApprovals, destMinDuration) = multisig.multisigSettings();
            assertEq(minApprovals, 1, "Should still be 1");
            assertEq(onlyListed, true, "Should still be true");
            assertEq(destMinDuration, 6 days, "Should still be 6 days");
        }

        vm.startPrank(alice);
    }

    // PROPOSAL CREATION

    function test_IncrementsTheProposalCounter() public {
        // increments the proposal counter

        assertEq(multisig.proposalCount(), 0, "Should have no proposals");

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        multisig.createProposal("", actions, optimisticPlugin, false);

        assertEq(multisig.proposalCount(), 1, "Should have 1 proposal");

        // 2
        multisig.createProposal("ipfs://", actions, optimisticPlugin, true);

        assertEq(multisig.proposalCount(), 2, "Should have 2 proposals");
    }

    function test_CreatesAndReturnsUniqueProposalIds() public {
        // creates unique proposal IDs for each proposal

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        assertEq(pid, 0, "Should be 0");

        // 2
        pid = multisig.createProposal("ipfs://", actions, optimisticPlugin, true);

        assertEq(pid, 1, "Should be 1");

        // 3
        pid = multisig.createProposal("ipfs://more", actions, optimisticPlugin, true);

        assertEq(pid, 2, "Should be 2");
    }

    function test_EmitsProposalCreated() public {
        // emits the `ProposalCreated` event

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 0,
            creator: alice,
            metadata: "",
            startDate: uint64(block.timestamp),
            endDate: 10 days + 1,
            actions: actions,
            allowFailureMap: 0
        });
        multisig.createProposal("", actions, optimisticPlugin, true);

        // 2
        vm.startPrank(bob);

        actions = new IDAO.Action[](1);
        actions[0].to = carol;
        actions[0].value = 1 ether;
        address[] memory addrs = new address[](1);
        actions[0].data = abi.encodeCall(Multisig.addAddresses, (addrs));

        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 1,
            creator: bob,
            metadata: "ipfs://",
            startDate: uint64(block.timestamp),
            endDate: 10 days + 1,
            actions: actions,
            allowFailureMap: 0
        });
        multisig.createProposal("ipfs://", actions, optimisticPlugin, false);
    }

    function test_RevertsIfSettingsChangedInSameBlock() public {
        // reverts if the multisig settings have changed in the same block

        // Deploy a new multisig instance
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: false, minApprovals: 3, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings)))
        );

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalCreationForbidden.selector, alice));
        multisig.createProposal("", actions, optimisticPlugin, false);

        // Next block
        vm.roll(block.number + 1);
        multisig.createProposal("", actions, optimisticPlugin, false);
    }

    function test_CreatesWhenUnlistedAccountsAllowed() public {
        // creates a proposal when unlisted accounts are allowed

        builder = new DaoBuilder();
        (dao, optimisticPlugin, multisig,,,) = builder.withMultisigMember(alice).withoutOnlyListed().build();

        vm.startPrank(randomWallet);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        multisig.createProposal("", actions, optimisticPlugin, false);
    }

    function test_RevertsWhenOnlyListedAndTheWalletIsNotListed() public {
        // reverts if the user is not on the list and only listed accounts can create proposals

        vm.startPrank(randomWallet);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalCreationForbidden.selector, randomWallet));
        multisig.createProposal("", actions, optimisticPlugin, false);
    }

    function test_RevertsWhenCreatorWasListedBeforeButNotNow() public {
        // reverts if `_msgSender` is not listed although she was listed in the last block

        // Deploy a new multisig instance
        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        address[] memory addrs = new address[](1);
        addrs[0] = alice;

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, addrs, settings)))
        );
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        vm.roll(block.number + 1);

        // Add+remove
        addrs[0] = bob;
        multisig.addAddresses(addrs);

        addrs[0] = alice;
        multisig.removeAddresses(addrs);

        // Alice cannot create now
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalCreationForbidden.selector, alice));
        multisig.createProposal("", actions, optimisticPlugin, false);

        // Bob can create now
        vm.startPrank(bob);

        multisig.createProposal("", actions, optimisticPlugin, false);

        assertEq(multisig.isListed(alice), false, "Should not be listed");
        assertEq(multisig.isListed(bob), true, "Should be listed");
    }

    function test_CreatesProposalWithoutApprovingIfUnspecified() public {
        // creates a proposal successfully and does not approve if not specified

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal(
            "",
            actions,
            optimisticPlugin,
            false // approveProposal
        );

        assertEq(multisig.hasApproved(pid, alice), false, "Should not have approved");
        (, uint16 approvals,,,,) = multisig.getProposal(pid);
        assertEq(approvals, 0, "Should be 0");

        multisig.approve(pid, false);

        assertEq(multisig.hasApproved(pid, alice), true, "Should have approved");
        (, approvals,,,,) = multisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");
    }

    function test_CreatesAndApprovesWhenSpecified() public {
        // creates a proposal successfully and approves if specified

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal(
            "",
            actions,
            optimisticPlugin,
            true // approveProposal
        );
        assertEq(multisig.hasApproved(pid, alice), true, "Should have approved");
        (, uint16 approvals,,,,) = multisig.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");
    }

    // CAN APPROVE

    function testFuzz_CanApproveReturnsfFalseIfNotCreated(uint256 randomProposalId) public view {
        // returns `false` if the proposal doesn't exist

        assertEq(multisig.canApprove(randomProposalId, alice), false, "Should be false");
        assertEq(multisig.canApprove(randomProposalId, bob), false, "Should be false");
        assertEq(multisig.canApprove(randomProposalId, carol), false, "Should be false");
        assertEq(multisig.canApprove(randomProposalId, david), false, "Should be false");
    }

    function testFuzz_CanApproveReturnsfFalseIfNotListed(address randomWallet) public {
        // returns `false` if the approver is not listed

        {
            // Deploy a new multisig instance (more efficient than the builder for fuzz testing)
            Multisig.MultisigSettings memory settings =
                Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
            address[] memory signers = new address[](1);
            signers[0] = alice;

            multisig = Multisig(
                createProxyAndCall(
                    address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings))
                )
            );
            vm.roll(block.number + 1);
        }

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // ko
        if (randomWallet != alice) {
            assertEq(multisig.canApprove(pid, randomWallet), false, "Should be false");
        }

        // static ko
        assertEq(multisig.canApprove(pid, randomWallet), false, "Should be false");

        // static ok
        assertEq(multisig.canApprove(pid, alice), true, "Should be true");
    }

    function test_CanApproveReturnsFalseIfApproved() public {
        // returns `false` if the approver has already approved

        builder = new DaoBuilder();
        (dao, optimisticPlugin, multisig,,,) = builder.withMultisigMember(alice).withMultisigMember(bob)
            .withMultisigMember(carol).withMultisigMember(david).withMinApprovals(4).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        assertEq(multisig.canApprove(pid, alice), true, "Should be true");
        multisig.approve(pid, false);
        assertEq(multisig.canApprove(pid, alice), false, "Should be false");

        // Bob
        assertEq(multisig.canApprove(pid, bob), true, "Should be true");
        vm.startPrank(bob);
        multisig.approve(pid, false);
        assertEq(multisig.canApprove(pid, bob), false, "Should be false");

        // Carol
        assertEq(multisig.canApprove(pid, carol), true, "Should be true");
        vm.startPrank(carol);
        multisig.approve(pid, false);
        assertEq(multisig.canApprove(pid, carol), false, "Should be false");

        // David
        assertEq(multisig.canApprove(pid, david), true, "Should be true");
        vm.startPrank(david);
        multisig.approve(pid, false);
        assertEq(multisig.canApprove(pid, david), false, "Should be false");
    }

    function test_CanApproveReturnsFalseIfExpired() public {
        // returns `false` if the proposal has ended

        uint64 startDate = 10;
        vm.warp(startDate);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        (,, Multisig.ProposalParameters memory parameters,,,) = multisig.getProposal(pid);
        assertEq(parameters.expirationDate, startDate + 10 days, "Incorrect expiration");

        assertEq(multisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(startDate + 10 days - 1); // multisig expiration time - 1
        assertEq(multisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(startDate + 10 days); // multisig expiration time
        assertEq(multisig.canApprove(pid, alice), false, "Should be false");

        // Start later
        startDate = 5 days;
        vm.warp(startDate);
        pid = multisig.createProposal("", actions, optimisticPlugin, false);

        assertEq(multisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(block.timestamp + 10 days - 1); // expiration time - 1
        assertEq(multisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(block.timestamp + 1); // expiration time
        assertEq(multisig.canApprove(pid, alice), false, "Should be false");
    }

    function test_CanApproveReturnsFalseIfExecuted() public {
        // returns `false` if the proposal is already executed

        dao.grant(address(optimisticPlugin), address(multisig), optimisticPlugin.PROPOSER_PERMISSION_ID());

        bool executed;
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, false);

        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);

        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, true); // auto execute

        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // David cannot approve
        assertEq(multisig.canApprove(pid, david), false, "Should be false");

        vm.startPrank(alice);
    }

    function test_CanApproveReturnsTrueIfListed() public {
        // returns `true` if the approver is listed

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        assertEq(multisig.canApprove(pid, alice), true, "Should be true");
        assertEq(multisig.canApprove(pid, bob), true, "Should be true");
        assertEq(multisig.canApprove(pid, carol), true, "Should be true");
        assertEq(multisig.canApprove(pid, david), true, "Should be true");

        // new instance
        builder = new DaoBuilder();
        (dao, optimisticPlugin, multisig,,,) = builder.withMultisigMember(randomWallet).withoutOnlyListed().build();

        // now ko
        actions = new IDAO.Action[](0);
        pid = multisig.createProposal("", actions, optimisticPlugin, false);

        assertEq(multisig.canApprove(pid, alice), false, "Should be false");
        assertEq(multisig.canApprove(pid, bob), false, "Should be false");
        assertEq(multisig.canApprove(pid, carol), false, "Should be false");
        assertEq(multisig.canApprove(pid, david), false, "Should be false");

        // ok
        assertEq(multisig.canApprove(pid, randomWallet), true, "Should be true");
    }

    // HAS APPROVED

    function test_HasApprovedReturnsFalseWhenNotApproved() public {
        // returns `false` if user hasn't approved yet

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        assertEq(multisig.hasApproved(pid, alice), false, "Should be false");
        assertEq(multisig.hasApproved(pid, bob), false, "Should be false");
        assertEq(multisig.hasApproved(pid, carol), false, "Should be false");
        assertEq(multisig.hasApproved(pid, david), false, "Should be false");
    }

    function test_HasApprovedReturnsTrueWhenUserApproved() public {
        // returns `true` if user has approved

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        assertEq(multisig.hasApproved(pid, alice), false, "Should be false");
        multisig.approve(pid, false);
        assertEq(multisig.hasApproved(pid, alice), true, "Should be true");

        // Bob
        vm.startPrank(bob);
        assertEq(multisig.hasApproved(pid, bob), false, "Should be false");
        multisig.approve(pid, false);
        assertEq(multisig.hasApproved(pid, bob), true, "Should be true");

        // Carol
        vm.startPrank(carol);
        assertEq(multisig.hasApproved(pid, carol), false, "Should be false");
        multisig.approve(pid, false);
        assertEq(multisig.hasApproved(pid, carol), true, "Should be true");

        // David
        vm.startPrank(david);
        assertEq(multisig.hasApproved(pid, david), false, "Should be false");
        multisig.approve(pid, false);
        assertEq(multisig.hasApproved(pid, david), true, "Should be true");
    }

    // APPROVE

    function testFuzz_ApproveRevertsIfNotCreated(uint256 randomProposalId) public {
        // Reverts if the proposal doesn't exist

        switchTo(alice);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, alice));
        multisig.approve(randomProposalId, false);

        // 2
        switchTo(bob);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, bob));
        multisig.approve(randomProposalId, false);

        // 3
        switchTo(carol);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, carol));
        multisig.approve(randomProposalId, true);

        // 4
        switchTo(david);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, randomProposalId, david));
        multisig.approve(randomProposalId, true);
    }

    function testFuzz_ApproveRevertsIfNotListed(address randomSigner) public {
        // Reverts if the signer is not listed

        builder = new DaoBuilder();
        (,, multisig,,,) = builder.withMultisigMember(alice).withMinApprovals(1).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        if (randomSigner == alice) {
            return;
        }

        switchTo(randomSigner);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, randomSigner));
        multisig.approve(pid, false);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, randomSigner));
        multisig.approve(pid, true);
    }

    function test_ApproveRevertsIfAlreadyApproved() public {
        // reverts when approving multiple times

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, true);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, alice));
        multisig.approve(pid, true);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, true);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, bob));
        multisig.approve(pid, false);

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, carol));
        multisig.approve(pid, true);
    }

    function test_ApprovesWithTheSenderAddress() public {
        // approves with the msg.sender address
        // Same as test_HasApprovedReturnsTrueWhenUserApproved()

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        assertEq(multisig.hasApproved(pid, alice), false, "Should be false");
        multisig.approve(pid, false);
        assertEq(multisig.hasApproved(pid, alice), true, "Should be true");

        // Bob
        vm.startPrank(bob);
        assertEq(multisig.hasApproved(pid, bob), false, "Should be false");
        multisig.approve(pid, false);
        assertEq(multisig.hasApproved(pid, bob), true, "Should be true");

        // Carol
        vm.startPrank(carol);
        assertEq(multisig.hasApproved(pid, carol), false, "Should be false");
        multisig.approve(pid, false);
        assertEq(multisig.hasApproved(pid, carol), true, "Should be true");

        // David
        vm.startPrank(david);
        assertEq(multisig.hasApproved(pid, david), false, "Should be false");
        multisig.approve(pid, false);
        assertEq(multisig.hasApproved(pid, david), true, "Should be true");
    }

    function test_ApproveRevertsIfExpired() public {
        // reverts if the proposal has ended

        uint64 expirationTime = uint64(block.timestamp) + 10 days;

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        assertEq(multisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(expirationTime);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, alice));
        multisig.approve(pid, false);

        vm.warp(expirationTime + 15 days);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, alice));
        multisig.approve(pid, false);

        // 2
        vm.warp(1000);
        expirationTime = uint64(block.timestamp) + 10 days;
        pid = multisig.createProposal("", actions, optimisticPlugin, false);

        assertEq(multisig.canApprove(pid, alice), true, "Should be true");

        vm.warp(expirationTime);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, alice));
        multisig.approve(pid, true);

        vm.warp(expirationTime + 500);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, alice));
        multisig.approve(pid, true);
    }

    function test_ApproveRevertsIfExecuted() public {
        // reverts if the proposal has ended

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);
        multisig.approve(pid, false);
        switchTo(bob);
        multisig.approve(pid, false);
        switchTo(carol);
        multisig.approve(pid, false);

        multisig.execute(pid);
        (bool executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, carol));
        multisig.approve(pid, false);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, pid, carol));
        multisig.approve(pid, true);
    }

    function test_ApprovingProposalsEmits() public {
        // Approving a proposal emits the Approved event

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        vm.expectEmit();
        emit Approved(pid, alice);
        multisig.approve(pid, false);

        // Bob
        vm.startPrank(bob);
        vm.expectEmit();
        emit Approved(pid, bob);
        multisig.approve(pid, false);

        // Carol
        vm.startPrank(carol);
        vm.expectEmit();
        emit Approved(pid, carol);
        multisig.approve(pid, false);

        // David (even if it already passed)
        vm.startPrank(david);
        vm.expectEmit();
        emit Approved(pid, david);
        multisig.approve(pid, false);
    }

    // CAN EXECUTE

    function testFuzz_CanExecuteReturnsFalseIfNotCreated(uint256 randomProposalId) public view {
        // returns `false` if the proposal doesn't exist

        assertEq(multisig.canExecute(randomProposalId), false, "Should be false");
    }

    function test_CanExecuteReturnsFalseIfBelowMinApprovals() public {
        // returns `false` if the proposal has not reached the minimum approvals yet
        (dao, optimisticPlugin, multisig,,,) = builder.withMinApprovals(2).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), false, "Should be false");

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), true, "Should be true");

        vm.startPrank(alice);

        // More approvals required (4)
        (dao, optimisticPlugin, multisig,,,) = builder.withMinApprovals(4).build();

        pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), false, "Should be false");

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), false, "Should be false");

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), false, "Should be false");

        // David
        vm.startPrank(david);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), true, "Should be true");
    }

    function test_CanExecuteReturnsFalseIfExpired() public {
        // returns `false` if the proposal has ended

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        multisig.approve(pid, false);
        vm.startPrank(bob);
        multisig.approve(pid, false);
        vm.startPrank(carol);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + 10 days - 1);
        assertEq(multisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + 1);
        assertEq(multisig.canExecute(pid), false, "Should be false");

        // 2
        vm.warp(50 days);
        actions = new IDAO.Action[](0);
        pid = multisig.createProposal("", actions, optimisticPlugin, false);

        vm.startPrank(alice);
        multisig.approve(pid, false);
        vm.startPrank(bob);
        multisig.approve(pid, false);
        vm.startPrank(carol);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + 10 days - 1);
        assertEq(multisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + 1);
        assertEq(multisig.canExecute(pid), false, "Should be false");
    }

    function test_CanExecuteReturnsFalseIfExecuted() public {
        // returns `false` if the proposal is already executed

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, false);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);

        assertEq(multisig.canExecute(pid), true, "Should be true");
        multisig.execute(pid);

        assertEq(multisig.canExecute(pid), false, "Should be false");
    }

    function test_CanExecuteReturnsTrueWhenAllGood() public {
        // returns `true` if the proposal can be executed

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);
        assertEq(multisig.canExecute(pid), false, "Should be false");

        // Alice
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), false, "Should be false");

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), false, "Should be false");

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);

        assertEq(multisig.canExecute(pid), true, "Should be true");
    }

    // EXECUTE

    function testFuzz_ExecuteRevertsIfNotCreated(uint256 randomProposalId) public {
        // reverts if the proposal doesn't exist

        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, randomProposalId));
        multisig.execute(randomProposalId);
    }

    function test_ExecuteRevertsIfBelowMinApprovals() public {
        // reverts if minApprovals is not met yet

        (dao, optimisticPlugin, multisig,,,) = builder.withMinApprovals(2).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, false);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, pid));
        multisig.execute(pid);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);
        multisig.execute(pid); // ok

        vm.startPrank(alice);

        // More approvals required (4)
        (dao, optimisticPlugin, multisig,,,) = builder.withMinApprovals(4).build();

        pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        multisig.approve(pid, false);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, pid));
        multisig.execute(pid);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, pid));
        multisig.execute(pid);

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, pid));
        multisig.execute(pid);

        // David
        vm.startPrank(david);
        multisig.approve(pid, false);
        multisig.execute(pid);
    }

    function test_ExecuteRevertsIfExpired() public {
        // reverts if the proposal has expired

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        multisig.approve(pid, false);
        vm.startPrank(bob);
        multisig.approve(pid, false);
        vm.startPrank(carol);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + 10 days);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, pid));
        multisig.execute(pid);

        vm.warp(100 days);

        // 2
        pid = multisig.createProposal("", actions, optimisticPlugin, false);

        vm.startPrank(alice);
        multisig.approve(pid, false);
        vm.startPrank(bob);
        multisig.approve(pid, false);
        vm.startPrank(carol);
        multisig.approve(pid, false);
        assertEq(multisig.canExecute(pid), true, "Should be true");

        vm.warp(block.timestamp + 10 days);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, pid));
        multisig.execute(pid);

        vm.startPrank(alice);
    }

    function test_ExecuteRevertsWhenAlreadyExecuted() public {
        // executes if the minimum approval is met when multisig with the `tryExecution` option

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, false);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);

        assertEq(multisig.canExecute(pid), true, "Should be true");
        multisig.execute(pid);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, pid));
        multisig.execute(pid);
    }

    function test_ExecuteEmitsEvents() public {
        // emits the `ProposalExecuted` and `ProposalCreated` events

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, false);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);

        // event
        vm.expectEmit();
        emit Executed(pid);
        uint256 targetPid = uint256(block.timestamp) << 128 | uint256(block.timestamp + 10 days) << 64;
        vm.expectEmit();
        emit ProposalCreated(
            targetPid, address(multisig), uint64(block.timestamp), uint64(block.timestamp) + 10 days, "", actions, 0
        );
        multisig.execute(pid);

        // 2
        (dao, optimisticPlugin, multisig,,,) = builder.withDuration(50 days).build();

        vm.warp(5000);
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        pid = multisig.createProposal("ipfs://", actions, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        multisig.approve(pid, false);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);

        // events
        vm.expectEmit();
        emit Executed(pid);
        targetPid = (uint256(block.timestamp) << 128 | uint256(block.timestamp + 50 days) << 64);
        vm.expectEmit();
        emit ProposalCreated(
            targetPid, address(multisig), uint64(block.timestamp), 5000 + 50 days, "ipfs://", actions, 0
        );
        multisig.execute(pid);
    }

    function test_ExecutesWhenApprovingWithTryExecutionAndEnoughApprovals() public {
        // executes if the minimum approval is met when multisig with the `tryExecution` option

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);
        (bool executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Alice
        multisig.approve(pid, true);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, true);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, true);

        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");
    }

    function test_ExecuteEmitsWhenAutoExecutedFromApprove() public {
        // emits the `Approved`, `ProposalExecuted`, and `ProposalCreated` events if execute is called inside the `approve` method

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, true);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, true);

        // Carol
        vm.startPrank(carol);
        vm.expectEmit();
        emit Approved(pid, carol);
        vm.expectEmit();
        emit Executed(pid);

        uint256 targetPid = (uint256(block.timestamp) << 128 | uint256(block.timestamp + 10 days) << 64);
        vm.expectEmit();
        emit ProposalCreated(
            targetPid, address(multisig), uint64(block.timestamp), uint64(block.timestamp) + 10 days, "", actions, 0
        );
        multisig.approve(pid, true);

        // 2
        vm.warp(5 days);
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        pid = multisig.createProposal("ipfs://", actions, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        multisig.approve(pid, true);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, true);

        // Carol
        vm.startPrank(carol);
        vm.expectEmit();
        emit Approved(pid, carol);
        vm.expectEmit();
        emit Executed(pid);

        targetPid = (uint256(5 days) << 128 | uint256(5 days + 10 days) << 64) + 1;
        vm.expectEmit();
        emit ProposalCreated(
            targetPid, // foreign pid
            address(multisig),
            uint64(block.timestamp),
            uint64(block.timestamp) + 10 days,
            "ipfs://",
            actions,
            0
        );
        multisig.approve(pid, true);

        // 3
        (dao, optimisticPlugin, multisig,,,) = builder.withDuration(50 days).build();

        vm.warp(7 days);
        actions = new IDAO.Action[](1);
        actions[0].value = 5 ether;
        actions[0].to = address(carol);
        actions[0].data = hex"44556677";
        pid = multisig.createProposal("ipfs://...", actions, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        multisig.approve(pid, true);

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, true);

        // Carol
        vm.startPrank(carol);
        vm.expectEmit();
        emit Approved(pid, carol);
        vm.expectEmit();
        emit Executed(pid);

        targetPid = (uint256(7 days) << 128 | uint256(7 days + 50 days) << 64);
        vm.expectEmit();
        emit ProposalCreated(targetPid, address(multisig), 7 days, 7 days + 50 days, "ipfs://...", actions, 0);
        multisig.approve(pid, true);
    }

    function test_ExecutesWithEnoughApprovalsOnTime() public {
        // executes if the minimum approval is met

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, false);
        (bool executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        multisig.execute(pid);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // 2
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        pid = multisig.createProposal("ipfs://", actions, optimisticPlugin, false);

        // Alice
        vm.startPrank(alice);
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        multisig.execute(pid);

        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");
    }

    function test_ExecuteWhenPassedAndCalledByAnyone() public {
        // executes if the minimum approval is met and can be called by an unlisted accounts

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 pid = multisig.createProposal("", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, false);
        (bool executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        vm.startPrank(randomWallet);
        multisig.execute(pid);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // 2
        vm.startPrank(alice);

        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        pid = multisig.createProposal("ipfs://", actions, optimisticPlugin, false);

        // Alice
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.startPrank(bob);
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.startPrank(carol);
        multisig.approve(pid, false);
        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        vm.startPrank(randomWallet);
        multisig.execute(pid);

        (executed,,,,,) = multisig.getProposal(pid);
        assertEq(executed, true, "Should be executed");
    }

    function test_GetProposalReturnsTheRightValues() public {
        // Get proposal returns the right values

        bool executed;
        uint16 approvals;
        Multisig.ProposalParameters memory parameters;
        bytes memory metadataURI;
        IDAO.Action[] memory actions;
        OptimisticTokenVotingPlugin destPlugin;

        vm.warp(10);

        IDAO.Action[] memory createActions = new IDAO.Action[](3);
        createActions[0].to = alice;
        createActions[0].value = 1 ether;
        createActions[0].data = hex"001122334455";
        createActions[1].to = bob;
        createActions[1].value = 2 ether;
        createActions[1].data = hex"112233445566";
        createActions[2].to = carol;
        createActions[2].value = 3 ether;
        createActions[2].data = hex"223344556677";

        uint256 pid = multisig.createProposal("ipfs://metadata", createActions, optimisticPlugin, false);
        assertEq(pid, 0, "PID should be 0");

        // Check round 1
        (executed, approvals, parameters, metadataURI, actions, destPlugin) = multisig.getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 0, "Should be 0");

        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, block.timestamp + 10 days, "Incorrect expirationDate");

        assertEq(actions.length, 3, "Should be 3");

        assertEq(actions[0].to, alice, "Incorrect to");
        assertEq(actions[0].value, 1 ether, "Incorrect value");
        assertEq(actions[0].data, hex"001122334455", "Incorrect data");
        assertEq(actions[1].to, bob, "Incorrect to");
        assertEq(actions[1].value, 2 ether, "Incorrect value");
        assertEq(actions[1].data, hex"112233445566", "Incorrect data");
        assertEq(actions[2].to, carol, "Incorrect to");
        assertEq(actions[2].value, 3 ether, "Incorrect value");
        assertEq(actions[2].data, hex"223344556677", "Incorrect data");

        assertEq(metadataURI, "ipfs://metadata", "Incorrect metadata URI");
        assertEq(address(destPlugin), address(optimisticPlugin), "Incorrect destPlugin");

        // Approve
        multisig.approve(pid, false);

        // Check round 2
        (executed, approvals, parameters, metadataURI, actions, destPlugin) = multisig.getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 1, "Should be 1");

        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, block.timestamp + 10 days, "Incorrect expirationDate");

        assertEq(actions.length, 3, "Should be 3");

        assertEq(actions[0].to, alice, "Incorrect to");
        assertEq(actions[0].value, 1 ether, "Incorrect value");
        assertEq(actions[0].data, hex"001122334455", "Incorrect data");
        assertEq(actions[1].to, bob, "Incorrect to");
        assertEq(actions[1].value, 2 ether, "Incorrect value");
        assertEq(actions[1].data, hex"112233445566", "Incorrect data");
        assertEq(actions[2].to, carol, "Incorrect to");
        assertEq(actions[2].value, 3 ether, "Incorrect value");
        assertEq(actions[2].data, hex"223344556677", "Incorrect data");

        assertEq(metadataURI, "ipfs://metadata", "Incorrect metadata URI");
        assertEq(address(destPlugin), address(optimisticPlugin), "Incorrect destPlugin");

        // Approve
        vm.startPrank(bob);
        multisig.approve(pid, false);
        vm.startPrank(carol);
        multisig.approve(pid, false);

        // Check round 3
        (executed, approvals, parameters, metadataURI, actions, destPlugin) = multisig.getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, block.timestamp + 10 days, "Incorrect expirationDate");

        assertEq(actions.length, 3, "Should be 3");

        assertEq(actions[0].to, alice, "Incorrect to");
        assertEq(actions[0].value, 1 ether, "Incorrect value");
        assertEq(actions[0].data, hex"001122334455", "Incorrect data");
        assertEq(actions[1].to, bob, "Incorrect to");
        assertEq(actions[1].value, 2 ether, "Incorrect value");
        assertEq(actions[1].data, hex"112233445566", "Incorrect data");
        assertEq(actions[2].to, carol, "Incorrect to");
        assertEq(actions[2].value, 3 ether, "Incorrect value");
        assertEq(actions[2].data, hex"223344556677", "Incorrect data");

        assertEq(metadataURI, "ipfs://metadata", "Incorrect metadata URI");
        assertEq(address(destPlugin), address(optimisticPlugin), "Incorrect destPlugin");

        // Execute
        vm.startPrank(alice);
        multisig.execute(pid);

        // Check round 4
        (executed, approvals, parameters, metadataURI, actions, destPlugin) = multisig.getProposal(pid);

        assertEq(executed, true, "Should be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, block.timestamp + 10 days, "Incorrect expirationDate");

        assertEq(actions.length, 3, "Should be 3");

        assertEq(actions[0].to, alice, "Incorrect to");
        assertEq(actions[0].value, 1 ether, "Incorrect value");
        assertEq(actions[0].data, hex"001122334455", "Incorrect data");
        assertEq(actions[1].to, bob, "Incorrect to");
        assertEq(actions[1].value, 2 ether, "Incorrect value");
        assertEq(actions[1].data, hex"112233445566", "Incorrect data");
        assertEq(actions[2].to, carol, "Incorrect to");
        assertEq(actions[2].value, 3 ether, "Incorrect value");
        assertEq(actions[2].data, hex"223344556677", "Incorrect data");

        assertEq(metadataURI, "ipfs://metadata", "Incorrect metadata URI");
        assertEq(address(destPlugin), address(optimisticPlugin), "Incorrect destPlugin");

        // New multisig, new settings
        vm.startPrank(alice);

        // Deploy new instances
        (dao, optimisticPlugin, multisig,,,) = builder.withMinApprovals(2).build();

        createActions = new IDAO.Action[](2);
        createActions[1].to = alice;
        createActions[1].value = 1 ether;
        createActions[1].data = hex"001122334455";
        createActions[0].to = carol;
        createActions[0].value = 3 ether;
        createActions[0].data = hex"223344556677";

        vm.warp(50); // Timestamp = 50

        pid = multisig.createProposal("ipfs://different-metadata", createActions, optimisticPlugin, true);
        assertEq(pid, 0, "PID should be 0");

        // Check round 1
        (executed, approvals, parameters, metadataURI, actions, destPlugin) = multisig.getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 1, "Should be 1");

        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, block.timestamp + 10 days, "Incorrect expirationDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(metadataURI, "ipfs://different-metadata", "Incorrect metadata URI");
        assertEq(address(destPlugin), address(optimisticPlugin), "Incorrect destPlugin");

        // Approve
        vm.startPrank(bob);
        multisig.approve(pid, false);

        // Check round 2
        (executed, approvals, parameters, metadataURI, actions, destPlugin) = multisig.getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 2, "Should be 2");

        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, block.timestamp + 10 days, "Incorrect expirationDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(metadataURI, "ipfs://different-metadata", "Incorrect metadata URI");
        assertEq(address(destPlugin), address(optimisticPlugin), "Incorrect destPlugin");

        // Approve
        vm.startPrank(carol);
        multisig.approve(pid, false);

        // Check round 3
        (executed, approvals, parameters, metadataURI, actions, destPlugin) = multisig.getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, block.timestamp + 10 days, "Incorrect expirationDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(metadataURI, "ipfs://different-metadata", "Incorrect metadata URI");
        assertEq(address(destPlugin), address(optimisticPlugin), "Incorrect destPlugin");

        // Execute
        vm.startPrank(alice);
        multisig.execute(pid);

        // Check round 4
        (executed, approvals, parameters, metadataURI, actions, destPlugin) = multisig.getProposal(pid);

        assertEq(executed, true, "Should be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(parameters.snapshotBlock, block.number - 1, "Incorrect snapshotBlock");
        assertEq(parameters.expirationDate, block.timestamp + 10 days, "Incorrect expirationDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(metadataURI, "ipfs://different-metadata", "Incorrect metadata URI");
        assertEq(address(destPlugin), address(optimisticPlugin), "Incorrect destPlugin");
    }

    function test_ProxiedProposalHasTheSameSettingsAsTheOriginal() public {
        // Recreated proposal has the same settings and actions as registered here

        bool open;
        bool executed;
        OptimisticTokenVotingPlugin.ProposalParameters memory parameters;
        uint256 vetoTally;
        IDAO.Action[] memory actions;
        uint256 allowFailureMap;

        vm.warp(1 days);

        IDAO.Action[] memory createActions = new IDAO.Action[](3);
        createActions[0].to = alice;
        createActions[0].value = 1 ether;
        createActions[0].data = hex"001122334455";
        createActions[1].to = bob;
        createActions[1].value = 2 ether;
        createActions[1].data = hex"112233445566";
        createActions[2].to = carol;
        createActions[2].value = 3 ether;
        createActions[2].data = hex"223344556677";

        uint256 pid = multisig.createProposal("ipfs://metadata", createActions, optimisticPlugin, false);

        // Approve
        multisig.approve(pid, false);
        vm.startPrank(bob);
        multisig.approve(pid, false);
        vm.startPrank(carol);
        multisig.approve(pid, false);

        vm.startPrank(alice);
        multisig.execute(pid);

        // Check round
        uint256 targetPid = uint256(1 days) << 128 | uint256(1 days + 10 days) << 64; // start=1d, end=10d, counter=0
        (open, executed, parameters, vetoTally, actions, allowFailureMap) = optimisticPlugin.getProposal(targetPid);

        assertEq(open, true, "Should be open");
        assertEq(executed, false, "Should not be executed");
        assertEq(vetoTally, 0, "Should be 0");

        assertEq(parameters.metadataUri, "ipfs://metadata", "Incorrect target metadataUri");
        assertEq(parameters.vetoEndDate, 1 days + 10 days, "Incorrect target vetoEndDate");

        assertEq(actions.length, 3, "Should be 3");

        assertEq(actions[0].to, alice, "Incorrect to");
        assertEq(actions[0].value, 1 ether, "Incorrect value");
        assertEq(actions[0].data, hex"001122334455", "Incorrect data");
        assertEq(actions[1].to, bob, "Incorrect to");
        assertEq(actions[1].value, 2 ether, "Incorrect value");
        assertEq(actions[1].data, hex"112233445566", "Incorrect data");
        assertEq(actions[2].to, carol, "Incorrect to");
        assertEq(actions[2].value, 3 ether, "Incorrect value");
        assertEq(actions[2].data, hex"223344556677", "Incorrect data");

        assertEq(allowFailureMap, 0, "Should be 0");

        // New proposal
        vm.warp(2 days);

        createActions = new IDAO.Action[](2);
        createActions[1].to = alice;
        createActions[1].value = 1 ether;
        createActions[1].data = hex"001122334455";
        createActions[0].to = carol;
        createActions[0].value = 3 ether;
        createActions[0].data = hex"223344556677";

        pid = multisig.createProposal("ipfs://more-metadata", createActions, optimisticPlugin, false);

        // Approve
        multisig.approve(pid, false);
        vm.startPrank(bob);
        multisig.approve(pid, false);
        vm.startPrank(carol);
        multisig.approve(pid, false);

        vm.startPrank(alice);
        multisig.execute(pid);

        // Check round
        targetPid = (uint256(2 days) << 128 | uint256(2 days + 10 days) << 64) + 1;
        (open, executed, parameters, vetoTally, actions, allowFailureMap) = optimisticPlugin.getProposal(targetPid);

        assertEq(open, true, "Should be open");
        assertEq(executed, false, "Should not be executed");
        assertEq(vetoTally, 0, "Should be 0");

        assertEq(parameters.metadataUri, "ipfs://more-metadata", "Incorrect target metadataUri");
        assertEq(parameters.vetoEndDate, 2 days + 10 days, "Incorrect target vetoEndDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(allowFailureMap, 0, "Should be 0");
    }

    // Upgrade multisig

    function test_UpgradeToRevertsWhenCalledFromNonUpgrader() public {
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
    }

    function test_UpgradeToAndCallRevertsWhenCalledFromNonUpgrader() public {
        address initialImplementation = multisig.implementation();
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        address _newImplementation = address(new Multisig());

        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: false, minApprovals: 2, destinationProposalDuration: 14 days});

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
    }

    function test_UpgradeToSucceedsWhenCalledFromUpgrader() public {
        dao.grant(address(multisig), alice, multisig.UPGRADE_PLUGIN_PERMISSION_ID());

        address _newImplementation = address(new Multisig());

        vm.expectEmit();
        emit Upgraded(_newImplementation);

        multisig.upgradeTo(_newImplementation);

        assertEq(multisig.implementation(), address(_newImplementation));
    }

    function test_UpgradeToAndCallSucceedsWhenCalledFromUpgrader() public {
        dao.grant(address(multisig), alice, multisig.UPGRADE_PLUGIN_PERMISSION_ID());
        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        address _newImplementation = address(new Multisig());

        vm.expectEmit();
        emit Upgraded(_newImplementation);

        Multisig.MultisigSettings memory settings =
            Multisig.MultisigSettings({onlyListed: false, minApprovals: 2, destinationProposalDuration: 14 days});
        multisig.upgradeToAndCall(_newImplementation, abi.encodeCall(Multisig.updateMultisigSettings, (settings)));

        assertEq(multisig.implementation(), address(_newImplementation));
    }
}
