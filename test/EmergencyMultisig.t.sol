// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
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
import {createProxyAndCall} from "./helpers.sol";

contract EmergencyMultisigTest is AragonTest {
    DAO dao;
    EmergencyMultisig plugin;
    Multisig multisig;
    OptimisticTokenVotingPlugin optimisticPlugin;

    // Events/errors to be tested here (duplicate)
    event MultisigSettingsUpdated(bool onlyListed, uint16 indexed minApprovals, Addresslist addresslistSource);
    event MembersAdded(address[] members);
    event MembersRemoved(address[] members);

    error InvalidAddresslistUpdate(address member);
    error InvalidActions(uint256 proposalId);

    /// @notice The emergency multisig event
    event ProposalCreated(
        uint256 indexed proposalId, address indexed creator, bytes encryptedPayloadURI, bytes32 destinationActionsHash
    );
    /// @notice The OptimisticTokenVotingPlugin event
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 excludeArtifactndDate,
        bytes metadata,
        IDAO.Action[] actions,
        uint256 allowFailureMap
    );
    event Approved(uint256 indexed proposalId, address indexed approver);
    event Executed(uint256 indexed proposalId);
    event Upgraded(address indexed implementation);

    function setUp() public {
        switchTo(alice);

        (dao, plugin, multisig, optimisticPlugin) = makeDaoWithEmergencyMultisigAndOptimistic(alice);

        // Ensure that created proposals happen 1 block after the settings changed
        blockForward(1);
    }

    function test_RevertsIfTryingToReinitialize() public {
        // Deploy a new multisig instance
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: multisig});

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // Reinitialize should fail
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize(dao, settings);
    }

    function test_ShouldSetMinApprovals() public {
        // 2
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 2, addresslistSource: multisig});

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        (, uint16 minApprovals,) = plugin.multisigSettings();
        assertEq(minApprovals, uint16(2), "Incorrect minApprovals");

        // Redeploy with 1
        settings.minApprovals = 1;

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        (, minApprovals,) = plugin.multisigSettings();
        assertEq(minApprovals, uint16(1), "Incorrect minApprovals");
    }

    function test_ShouldSetOnlyListed() public {
        // Deploy with true
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: multisig});

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        (bool onlyListed,,) = plugin.multisigSettings();
        assertEq(onlyListed, true, "Incorrect onlyListed");

        // Redeploy with false
        settings.onlyListed = false;

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        (onlyListed,,) = plugin.multisigSettings();
        assertEq(onlyListed, false, "Incorrect onlyListed");
    }

    function test_ShouldSetAddresslistSource() public {
        // Deploy the default multisig as source
        EmergencyMultisig.MultisigSettings memory emSettings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: multisig});

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, emSettings))
            )
        );

        (,, Addresslist givenAddressListSource) = plugin.multisigSettings();
        assertEq(address(givenAddressListSource), address(multisig), "Incorrect addresslistSource");

        // Redeploy with a new addresslist source
        (, Multisig newMultisig,) = makeDaoWithMultisigAndOptimistic(alice);

        emSettings.addresslistSource = newMultisig;

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, emSettings))
            )
        );

        (,, givenAddressListSource) = plugin.multisigSettings();
        assertEq(address(givenAddressListSource), address(emSettings.addresslistSource), "Incorrect addresslistSource");
    }

    function test_ShouldEmitMultisigSettingsUpdatedOnInstall() public {
        // Deploy with true/3/default
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: multisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, uint16(3), multisig);

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // Deploy with false/2/new
        (, Multisig newMultisig,) = makeDaoWithMultisigAndOptimistic(alice);

        settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 2, addresslistSource: newMultisig});
        vm.expectEmit();
        emit MultisigSettingsUpdated(false, uint16(2), newMultisig);

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    // INTERFACES

    function test_DoesntSupportTheEmptyInterface() public view {
        bool supported = plugin.supportsInterface(0);
        assertEq(supported, false, "Should not support the empty interface");
    }

    function test_SupportsIERC165Upgradeable() public view {
        bool supported = plugin.supportsInterface(type(IERC165Upgradeable).interfaceId);
        assertEq(supported, true, "Should support IERC165Upgradeable");
    }

    function test_SupportsIPlugin() public view {
        bool supported = plugin.supportsInterface(type(IPlugin).interfaceId);
        assertEq(supported, true, "Should support IPlugin");
    }

    function test_SupportsIProposal() public view {
        bool supported = plugin.supportsInterface(type(IProposal).interfaceId);
        assertEq(supported, true, "Should support IProposal");
    }

    function test_SupportsIMembership() public view {
        bool supported = plugin.supportsInterface(type(IMembership).interfaceId);
        assertEq(supported, true, "Should support IMembership");
    }

    function test_SupportsIEmergencyMultisig() public view {
        bool supported = plugin.supportsInterface(type(IEmergencyMultisig).interfaceId);
        assertEq(supported, true, "Should support IEmergencyMultisig");
    }

    // UPDATE MULTISIG SETTINGS

    function test_ShouldntAllowMinApprovalsHigherThenAddrListLength() public {
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5,
            addresslistSource: multisig // Greater than 4 members
        });

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 4, 5));

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // Retry with onlyListed false
        settings = EmergencyMultisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 6,
            addresslistSource: multisig // Greater than 4 members
        });
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 4, 6));
        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    function test_ShouldNotAllowMinApprovalsZero() public {
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 0, addresslistSource: multisig});

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 1, 0));

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        // Retry with onlyListed false
        settings = EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 0, addresslistSource: multisig});
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.MinApprovalsOutOfBounds.selector, 1, 0));
        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );
    }

    function test_ShouldEmitMultisigSettingsUpdated() public {
        dao.grant(address(plugin), address(alice), plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // 1
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 1, addresslistSource: multisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 1, multisig);
        plugin.updateMultisigSettings(settings);

        // 2
        (, Multisig newMultisig,) = makeDaoWithMultisigAndOptimistic(alice);

        settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 2, addresslistSource: newMultisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 2, newMultisig);
        plugin.updateMultisigSettings(settings);

        // 3
        (, newMultisig,) = makeDaoWithMultisigAndOptimistic(alice);

        settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 3, addresslistSource: newMultisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 3, newMultisig);
        plugin.updateMultisigSettings(settings);

        // 4
        settings = EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 4, addresslistSource: multisig});

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 4, multisig);
        plugin.updateMultisigSettings(settings);
    }

    function test_onlyWalletWithPermissionsCanUpdateSettings() public {
        (, Multisig newMultisig,) = makeDaoWithMultisigAndOptimistic(alice);

        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 1, addresslistSource: newMultisig});
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                alice,
                plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
            )
        );
        plugin.updateMultisigSettings(settings);

        // Nothing changed
        (bool onlyListed, uint16 minApprovals, Addresslist currentSource) = plugin.multisigSettings();
        assertEq(onlyListed, true);
        assertEq(minApprovals, 3);
        assertEq(address(currentSource), address(multisig));

        // Retry with the permission
        dao.grant(address(plugin), alice, plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 1, newMultisig);
        plugin.updateMultisigSettings(settings);
    }

    function test_IsMemberShouldReturnWhenApropriate() public {
        assertEq(plugin.isMember(alice), true, "Should be a member");
        assertEq(plugin.isMember(bob), true, "Should be a member");
        assertEq(plugin.isMember(carol), true, "Should be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");

        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        address[] memory signers = new address[](1);
        signers[0] = bob;
        multisig.removeAddresses(signers);

        assertEq(plugin.isMember(alice), true, "Should be a member");
        assertEq(plugin.isMember(bob), false, "Should not be a member");
        assertEq(plugin.isMember(carol), true, "Should be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");

        // 2
        multisig.addAddresses(signers); // Add Bob back
        signers[0] = alice;
        multisig.removeAddresses(signers);

        assertEq(plugin.isMember(alice), false, "Should not be a member");
        assertEq(plugin.isMember(bob), true, "Should be a member");
        assertEq(plugin.isMember(carol), true, "Should be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");

        // 3
        multisig.addAddresses(signers); // Add Alice back
        signers[0] = carol;
        multisig.removeAddresses(signers);

        assertEq(plugin.isMember(alice), true, "Should be a member");
        assertEq(plugin.isMember(bob), true, "Should be a member");
        assertEq(plugin.isMember(carol), false, "Should not be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");

        // 4
        multisig.addAddresses(signers); // Add Carol back
        signers[0] = david;
        multisig.removeAddresses(signers);

        assertEq(plugin.isMember(alice), true, "Should be a member");
        assertEq(plugin.isMember(bob), true, "Should be a member");
        assertEq(plugin.isMember(carol), true, "Should be a member");
        assertEq(plugin.isMember(david), false, "Should not be a member");
    }

    function test_IsMemberIsListedShouldReturnTheSameValue() public {
        assertEq(multisig.isListed(alice), plugin.isMember(alice), "isMember isListed should be equal");
        assertEq(multisig.isListed(bob), plugin.isMember(bob), "isMember isListed should be equal");
        assertEq(multisig.isListed(carol), plugin.isMember(carol), "isMember isListed should be equal");
        assertEq(multisig.isListed(david), plugin.isMember(david), "isMember isListed should be equal");

        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        address[] memory signers = new address[](1);
        signers[0] = alice;
        multisig.removeAddresses(signers);

        assertEq(multisig.isListed(alice), plugin.isMember(alice), "isMember isListed should be equal");
        assertEq(multisig.isListed(bob), plugin.isMember(bob), "isMember isListed should be equal");
        assertEq(multisig.isListed(carol), plugin.isMember(carol), "isMember isListed should be equal");
        assertEq(multisig.isListed(david), plugin.isMember(david), "isMember isListed should be equal");

        // 2
        multisig.addAddresses(signers); // Add Alice back
        signers[0] = bob;
        multisig.removeAddresses(signers);

        assertEq(multisig.isListed(alice), plugin.isMember(alice), "isMember isListed should be equal");
        assertEq(multisig.isListed(bob), plugin.isMember(bob), "isMember isListed should be equal");
        assertEq(multisig.isListed(carol), plugin.isMember(carol), "isMember isListed should be equal");
        assertEq(multisig.isListed(david), plugin.isMember(david), "isMember isListed should be equal");

        // 3
        multisig.addAddresses(signers); // Add Bob back
        signers[0] = carol;
        multisig.removeAddresses(signers);

        assertEq(multisig.isListed(alice), plugin.isMember(alice), "isMember isListed should be equal");
        assertEq(multisig.isListed(bob), plugin.isMember(bob), "isMember isListed should be equal");
        assertEq(multisig.isListed(carol), plugin.isMember(carol), "isMember isListed should be equal");
        assertEq(multisig.isListed(david), plugin.isMember(david), "isMember isListed should be equal");

        // 4
        multisig.addAddresses(signers); // Add Carol back
        signers[0] = david;
        multisig.removeAddresses(signers);

        assertEq(multisig.isListed(alice), plugin.isMember(alice), "isMember isListed should be equal");
        assertEq(multisig.isListed(bob), plugin.isMember(bob), "isMember isListed should be equal");
        assertEq(multisig.isListed(carol), plugin.isMember(carol), "isMember isListed should be equal");
        assertEq(multisig.isListed(david), plugin.isMember(david), "isMember isListed should be equal");
    }

    function testFuzz_IsMemberIsFalseByDefault(uint256 _randomEntropy) public {
        // Deploy a new multisig instance
        Multisig.MultisigSettings memory mSettings =
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
        address[] memory signers = new address[](1);
        signers[0] = address(0x0); // 0x0... would be a member but the chance is negligible

        multisig = Multisig(
            createProxyAndCall(address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, mSettings)))
        );
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 1, addresslistSource: multisig});
        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        assertEq(
            plugin.isMember(vm.addr(uint256(keccak256(abi.encodePacked(_randomEntropy))))), false, "Should be false"
        );
    }

    function testFuzz_PermissionedUpdateSettings(address randomAccount) public {
        dao.grant(address(plugin), alice, plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        (bool onlyListed, uint16 minApprovals, Addresslist addresslistSource) = plugin.multisigSettings();
        assertEq(minApprovals, 3, "Should be 3");
        assertEq(onlyListed, true, "Should be true");
        assertEq(address(addresslistSource), address(multisig), "Incorrect addresslistSource");

        // in
        (, Multisig newMultisig,) = makeDaoWithMultisigAndOptimistic(alice);
        EmergencyMultisig.MultisigSettings memory newSettings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 2, addresslistSource: newMultisig});
        plugin.updateMultisigSettings(newSettings);

        Addresslist givenAddresslistSource;
        (onlyListed, minApprovals, givenAddresslistSource) = plugin.multisigSettings();
        assertEq(minApprovals, 2, "Should be 2");
        assertEq(onlyListed, false, "Should be false");
        assertEq(address(givenAddresslistSource), address(newMultisig), "Incorrect addresslistSource");

        // out
        newSettings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 1, addresslistSource: multisig});
        plugin.updateMultisigSettings(newSettings);
        (onlyListed, minApprovals, givenAddresslistSource) = plugin.multisigSettings();
        assertEq(minApprovals, 1, "Should be 1");
        assertEq(onlyListed, true, "Should be true");
        assertEq(address(givenAddresslistSource), address(multisig), "Incorrect addresslistSource");

        blockForward(1);

        // someone else
        if (randomAccount != alice && randomAccount != address(0)) {
            undoSwitch();
            switchTo(randomAccount);

            (, newMultisig,) = makeDaoWithMultisigAndOptimistic(alice);
            newSettings =
                EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 4, addresslistSource: newMultisig});

            vm.expectRevert(
                abi.encodeWithSelector(
                    DaoUnauthorized.selector,
                    address(dao),
                    address(plugin),
                    randomAccount,
                    plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
                )
            );
            plugin.updateMultisigSettings(newSettings);

            (onlyListed, minApprovals, givenAddresslistSource) = plugin.multisigSettings();
            assertEq(minApprovals, 1, "Should still be 1");
            assertEq(onlyListed, true, "Should still be true");
            assertEq(address(givenAddresslistSource), address(multisig), "Should still be multisig");
        }

        undoSwitch();
        switchTo(alice);
    }

    // PROPOSAL CREATION

    function test_IncrementsTheProposalCounter() public {
        // increments the proposal counter
        assertEq(plugin.proposalCount(), 0, "Should have no proposals");

        // 1
        plugin.createProposal(
            "ipfs://",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            false
        );

        assertEq(plugin.proposalCount(), 1, "Should have 1 proposal");

        // 2
        plugin.createProposal(
            "ipfs://more",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            true
        );

        assertEq(plugin.proposalCount(), 2, "Should have 2 proposals");
    }

    function test_CreatesAndReturnsUniqueProposalIds() public {
        // creates unique proposal IDs for each proposal

        // 1
        uint256 pid = plugin.createProposal(
            "", bytes32(0x1234000000000000000000000000000000000000000000000000000000000000), optimisticPlugin, true
        );

        assertEq(pid, 0, "Should be 0");

        // 2
        pid = plugin.createProposal(
            "ipfs://",
            bytes32(0x0000567800000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            false
        );

        assertEq(pid, 1, "Should be 1");

        // 3
        pid = plugin.createProposal(
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
        plugin.createProposal(
            "", bytes32(0x1234000000000000000000000000000000000000000000000000000000000000), optimisticPlugin, true
        );

        // 2
        undoSwitch();
        switchTo(bob);
        blockForward(1);

        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 1,
            creator: bob,
            encryptedPayloadURI: "ipfs://",
            destinationActionsHash: bytes32(0x0000567800000000000000000000000000000000000000000000000000000000)
        });
        plugin.createProposal(
            "ipfs://",
            bytes32(0x0000567800000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            false
        );

        // undo
        undoSwitch();
        switchTo(alice);
    }

    function test_RevertsIfSettingsChangedInSameBlock() public {
        // reverts if the multisig settings have changed in the same block

        (dao, plugin, multisig, optimisticPlugin) = makeDaoWithEmergencyMultisigAndOptimistic(alice);

        // 1
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, alice));
        plugin.createProposal("", bytes32(0), optimisticPlugin, false);

        // Next block
        blockForward(1);
        plugin.createProposal("", bytes32(0), optimisticPlugin, false);
    }

    function test_CreatesWhenUnlistedAccountsAllowed() public {
        // creates a proposal when unlisted accounts are allowed

        // Deploy a new instance with custom settings
        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 3, addresslistSource: multisig});

        plugin = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        undoSwitch();
        switchTo(randomWallet);
        blockForward(1);

        plugin.createProposal("", 0, optimisticPlugin, false);

        undoSwitch();
        switchTo(alice);
    }

    function test_RevertsWhenOnlyListedAndAnotherWalletCreates() public {
        // reverts if the user is not on the list and only listed accounts can create proposals

        undoSwitch();
        switchTo(randomWallet);
        blockForward(1);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, randomWallet));
        plugin.createProposal("", 0, optimisticPlugin, false);

        undoSwitch();
        switchTo(alice);
    }

    function test_RevertsWhenCreatorWasListedBeforeButNotNow() public {
        // reverts if `msg.sender` is not listed although she was listed in the last block

        dao.grant(address(multisig), alice, multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        // Remove
        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        multisig.removeAddresses(addrs);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, alice));
        plugin.createProposal("", 0, optimisticPlugin, false);

        multisig.addAddresses(addrs); // Add Alice back
        blockForward(1);
        plugin.createProposal("", 0, optimisticPlugin, false);

        // Add+remove
        addrs[0] = bob;
        multisig.removeAddresses(addrs);

        undoSwitch();
        switchTo(bob);

        // Bob cannot create now
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalCreationForbidden.selector, bob));
        plugin.createProposal("", 0, optimisticPlugin, false);

        undoSwitch();
        switchTo(alice);

        // Bob can create now
        multisig.addAddresses(addrs); // Add Bob back

        undoSwitch();
        switchTo(alice);

        plugin.createProposal("", 0, optimisticPlugin, false);
    }

    function test_CreatesProposalWithoutApprovingIfUnspecified() public {
        // creates a proposal successfully and does not approve if not specified

        uint256 pid = plugin.createProposal(
            "",
            0,
            optimisticPlugin,
            false // approveProposal
        );

        assertEq(plugin.hasApproved(pid, alice), false, "Should not have approved");
        (, uint16 approvals,,,,) = plugin.getProposal(pid);
        assertEq(approvals, 0, "Should be 0");

        plugin.approve(pid);

        assertEq(plugin.hasApproved(pid, alice), true, "Should have approved");
        (, approvals,,,,) = plugin.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");
    }

    function test_CreatesAndApprovesWhenSpecified() public {
        // creates a proposal successfully and approves if specified

        vm.expectEmit();
        emit Approved({proposalId: 0, approver: alice});
        plugin.createProposal(
            "ipfs://",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            true
        );

        uint256 pid = plugin.createProposal(
            "ipfs://",
            bytes32(0x1234000000000000000000000000000000000000000000000000000000000000),
            optimisticPlugin,
            true // approveProposal
        );
        assertEq(plugin.hasApproved(pid, alice), true, "Should have approved");
        (, uint16 approvals,,,,) = plugin.getProposal(pid);
        assertEq(approvals, 1, "Should be 1");
    }

    function test_HashActionsReturnsProperData() public view {
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].to = address(dao);
        actions[0].value = 1 ether;
        actions[0].data = hex"00112233";

        bytes32 h1 = plugin.hashActions(actions);

        // 2
        actions[0].to = bob;
        bytes32 h2 = plugin.hashActions(actions);
        assertNotEq(h1, h2, "Hashes should differ");

        // 3
        actions[0].value = 2 ether;
        bytes32 h3 = plugin.hashActions(actions);
        assertNotEq(h2, h3, "Hashes should differ");

        // 4
        actions[0].data = hex"00112235";
        bytes32 h4 = plugin.hashActions(actions);
        assertNotEq(h3, h4, "Hashes should differ");

        // 5
        actions = new IDAO.Action[](0);
        bytes32 h5 = plugin.hashActions(actions);
        assertNotEq(h4, h5, "Hashes should differ");

        // 5'
        bytes32 h5b = plugin.hashActions(actions);
        assertEq(h5, h5b, "Hashes should match");
    }

    // CAN APPROVE

    function testFuzz_CanApproveReturnsfFalseIfNotListed(address _randomWallet) public {
        // returns `false` if the approver is not listed

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory mSettings =
                Multisig.MultisigSettings({onlyListed: false, minApprovals: 1, destinationProposalDuration: 4 days});
            address[] memory signers = new address[](1);
            signers[0] = address(0x0);

            multisig = Multisig(
                createProxyAndCall(
                    address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, mSettings))
                )
            );
            // New emergency multisig using the above
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: false, minApprovals: 1, addresslistSource: multisig});
            plugin = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );

            blockForward(1);
        }

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        // ko
        if (_randomWallet != address(0x0)) {
            assertEq(plugin.canApprove(pid, _randomWallet), false, "Should be false");
        }

        // static ok
        assertEq(plugin.canApprove(pid, address(0)), true, "Should be true");
    }

    function test_CanApproveReturnsFalseIfApproved() public {
        // returns `false` if the approver has already approved
        {
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 4, addresslistSource: multisig});
            plugin = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
            blockForward(1);
        }

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        // Alice
        assertEq(plugin.canApprove(pid, alice), true, "Should be true");
        plugin.approve(pid);
        assertEq(plugin.canApprove(pid, alice), false, "Should be false");

        // Bob
        assertEq(plugin.canApprove(pid, bob), true, "Should be true");
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        assertEq(plugin.canApprove(pid, bob), false, "Should be false");

        // Carol
        assertEq(plugin.canApprove(pid, carol), true, "Should be true");
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        assertEq(plugin.canApprove(pid, carol), false, "Should be false");

        // David
        assertEq(plugin.canApprove(pid, david), true, "Should be true");
        undoSwitch();
        switchTo(david);
        plugin.approve(pid);
        assertEq(plugin.canApprove(pid, david), false, "Should be false");

        undoSwitch();
        switchTo(alice);
    }

    function test_CanApproveReturnsFalseIfExpired() public {
        // returns `false` if the proposal has ended

        setTime(0);

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        assertEq(plugin.canApprove(pid, alice), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD - 1); // multisig expiration time - 1
        assertEq(plugin.canApprove(pid, alice), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 1); // multisig expiration time
        assertEq(plugin.canApprove(pid, alice), false, "Should be false");

        // Start later
        setTime(1000);
        pid = plugin.createProposal("", 0, optimisticPlugin, false);

        assertEq(plugin.canApprove(pid, alice), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 1000); // expiration time - 1
        assertEq(plugin.canApprove(pid, alice), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 1001); // expiration time
        assertEq(plugin.canApprove(pid, alice), false, "Should be false");
    }

    function test_CanApproveReturnsFalseIfExecuted() public {
        // returns `false` if the proposal is already executed

        bool executed;
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);

        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);

        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid); // passed

        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        plugin.execute(pid, actions);

        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // David cannot approve
        assertEq(plugin.canApprove(pid, david), false, "Should be false");

        undoSwitch();
        switchTo(alice);
    }

    function test_CanApproveReturnsTrueIfListed() public {
        // returns `true` if the approver is listed

        setTime(10); // timestamp = 10

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        assertEq(plugin.canApprove(pid, alice), true, "Should be true");
        assertEq(plugin.canApprove(pid, bob), true, "Should be true");
        assertEq(plugin.canApprove(pid, carol), true, "Should be true");
        assertEq(plugin.canApprove(pid, david), true, "Should be true");

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings =
                Multisig.MultisigSettings({onlyListed: true, minApprovals: 1, destinationProposalDuration: 4 days});
            address[] memory signers = new address[](1);
            signers[0] = randomWallet;

            multisig = Multisig(
                createProxyAndCall(
                    address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings))
                )
            );
        }
        {
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 1, addresslistSource: multisig});

            plugin = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
            blockForward(1);
        }

        // now ko
        undoSwitch();
        switchTo(randomWallet);
        pid = plugin.createProposal("", 0, optimisticPlugin, false);

        assertEq(plugin.canApprove(pid, alice), false, "Should be false");
        assertEq(plugin.canApprove(pid, bob), false, "Should be false");
        assertEq(plugin.canApprove(pid, carol), false, "Should be false");
        assertEq(plugin.canApprove(pid, david), false, "Should be false");

        // ok
        assertEq(plugin.canApprove(pid, randomWallet), true, "Should be true");
    }

    // HAS APPROVED

    function test_HasApprovedReturnsFalseWhenNotApproved() public {
        // returns `false` if user hasn't approved yet

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        // Alice
        assertEq(plugin.hasApproved(pid, alice), false, "Should be false");
        assertEq(plugin.hasApproved(pid, bob), false, "Should be false");
        assertEq(plugin.hasApproved(pid, carol), false, "Should be false");
        assertEq(plugin.hasApproved(pid, david), false, "Should be false");
    }

    function test_HasApprovedReturnsTrueWhenUserApproved() public {
        // returns `true` if user has approved

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        // Alice
        assertEq(plugin.hasApproved(pid, alice), false, "Should be false");
        plugin.approve(pid);
        assertEq(plugin.hasApproved(pid, alice), true, "Should be true");

        // Bob
        undoSwitch();
        switchTo(bob);
        assertEq(plugin.hasApproved(pid, bob), false, "Should be false");
        plugin.approve(pid);
        assertEq(plugin.hasApproved(pid, bob), true, "Should be true");

        // Carol
        undoSwitch();
        switchTo(carol);
        assertEq(plugin.hasApproved(pid, carol), false, "Should be false");
        plugin.approve(pid);
        assertEq(plugin.hasApproved(pid, carol), true, "Should be true");

        // David
        undoSwitch();
        switchTo(david);
        assertEq(plugin.hasApproved(pid, david), false, "Should be false");
        plugin.approve(pid);
        assertEq(plugin.hasApproved(pid, david), true, "Should be true");

        undoSwitch();
        switchTo(alice);
    }

    // APPROVE

    function test_ApproveRevertsIfApprovingMultipleTimes() public {
        // reverts when approving multiple times

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        plugin.approve(pid);

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, bob));
        plugin.approve(pid);

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, carol));
        plugin.approve(pid);

        undoSwitch();
        switchTo(alice);
    }

    function test_ApprovesWithTheSenderAddress() public {
        // approves with the msg.sender address
        // Same as test_HasApprovedReturnsTrueWhenUserApproved()

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        // Alice
        assertEq(plugin.hasApproved(pid, alice), false, "Should be false");
        plugin.approve(pid);
        assertEq(plugin.hasApproved(pid, alice), true, "Should be true");

        // Bob
        undoSwitch();
        switchTo(bob);
        assertEq(plugin.hasApproved(pid, bob), false, "Should be false");
        plugin.approve(pid);
        assertEq(plugin.hasApproved(pid, bob), true, "Should be true");

        // Carol
        undoSwitch();
        switchTo(carol);
        assertEq(plugin.hasApproved(pid, carol), false, "Should be false");
        plugin.approve(pid);
        assertEq(plugin.hasApproved(pid, carol), true, "Should be true");

        // David
        undoSwitch();
        switchTo(david);
        assertEq(plugin.hasApproved(pid, david), false, "Should be false");
        plugin.approve(pid);
        assertEq(plugin.hasApproved(pid, david), true, "Should be true");

        undoSwitch();
        switchTo(alice);
    }

    function test_ApproveRevertsIfExpired() public {
        // reverts if the proposal has ended

        setTime(0);

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        assertEq(plugin.canApprove(pid, alice), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 1);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        plugin.approve(pid);

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 15 days);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        plugin.approve(pid);

        // 2
        setTime(10); // timestamp = 10
        pid = plugin.createProposal("", 0, optimisticPlugin, false);

        assertEq(plugin.canApprove(pid, alice), true, "Should be true");

        setTime(10 + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 1);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        plugin.approve(pid);

        setTime(10 + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 500);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ApprovalCastForbidden.selector, pid, alice));
        plugin.approve(pid);
    }

    function test_ApprovingProposalsEmits() public {
        // Approving a proposal emits the Approved event

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        vm.expectEmit();
        emit Approved(pid, alice);
        plugin.approve(pid);

        // Bob
        undoSwitch();
        switchTo(bob);
        vm.expectEmit();
        emit Approved(pid, bob);
        plugin.approve(pid);

        // Carol
        undoSwitch();
        switchTo(carol);
        vm.expectEmit();
        emit Approved(pid, carol);
        plugin.approve(pid);

        // David (even if it already passed)
        undoSwitch();
        switchTo(david);
        vm.expectEmit();
        emit Approved(pid, david);
        plugin.approve(pid);

        undoSwitch();
        switchTo(alice);
    }

    // CAN EXECUTE

    function test_CanExecuteReturnsFalseIfBelowMinApprovals() public {
        // returns `false` if the proposal has not reached the minimum approvals yet

        {
            // Deploy a new multisig instance
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 2, addresslistSource: multisig});

            plugin = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
            blockForward(1);
        }
        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        undoSwitch();
        switchTo(alice);

        // More approvals required (4)

        {
            // Deploy a new multisig instance
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 4, addresslistSource: multisig});

            plugin = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
            blockForward(1);
        }

        pid = plugin.createProposal("", 0, optimisticPlugin, false);

        // Alice
        undoSwitch();
        switchTo(alice);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // David
        undoSwitch();
        switchTo(david);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        undoSwitch();
        switchTo(alice);
    }

    function test_CanExecuteReturnsFalseIfExpired() public {
        // returns `false` if the proposal has expired

        // 1
        setTime(0);

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);

        plugin.approve(pid);
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 1);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // 2
        setTime(0);

        pid = plugin.createProposal("", 0, optimisticPlugin, false);

        undoSwitch();
        switchTo(alice);
        plugin.approve(pid);
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 1);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        undoSwitch();
        switchTo(alice);
    }

    function test_CanExecuteReturnsFalseIfExecuted() public {
        // returns `false` if the proposal is already executed

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);

        assertEq(plugin.canExecute(pid), true, "Should be true");
        plugin.execute(pid, actions);

        assertEq(plugin.canExecute(pid), false, "Should be false");

        undoSwitch();
        switchTo(alice);
    }

    function test_CanExecuteReturnsTrueWhenAllGood() public {
        // returns `true` if the proposal can be executed

        uint256 pid = plugin.createProposal("", 0, optimisticPlugin, false);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Alice
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);

        assertEq(plugin.canExecute(pid), true, "Should be true");
    }

    // EXECUTE

    function test_ExecuteRevertsIfBelowMinApprovals() public {
        // reverts if minApprovals is not met yet

        {
            // Deploy a new multisig instance
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 2, addresslistSource: multisig});

            plugin = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
            dao.grant(address(optimisticPlugin), address(plugin), optimisticPlugin.PROPOSER_PERMISSION_ID());
            blockForward(1);
        }
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        plugin.execute(pid, actions);

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        plugin.execute(pid, actions); // ok

        // More approvals required (4)
        undoSwitch();
        switchTo(alice);

        {
            // Deploy a new multisig instance
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 4, addresslistSource: multisig});

            plugin = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
            dao.grant(address(optimisticPlugin), address(plugin), optimisticPlugin.PROPOSER_PERMISSION_ID());
            blockForward(1);
        }

        pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        undoSwitch();
        switchTo(alice);
        plugin.approve(pid);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        plugin.execute(pid, actions);

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        plugin.execute(pid, actions);

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        plugin.execute(pid, actions);

        // David
        undoSwitch();
        switchTo(david);
        plugin.approve(pid);
        plugin.execute(pid, actions);

        undoSwitch();
        switchTo(alice);
    }

    function test_ExecuteRevertsIfExpired() public {
        // reverts if the proposal has expired

        setTime(0);

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        plugin.approve(pid);
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        setTime(EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 1);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        plugin.execute(pid, actions);

        setTime(100 days);

        // 2
        pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        undoSwitch();
        switchTo(alice);
        plugin.approve(pid);
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        setTime(100 days + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD + 1);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        plugin.execute(pid, actions);

        undoSwitch();
        switchTo(alice);
    }

    function test_ExecuteRevertsWhenAlreadyExecuted() public {
        // executes if the minimum approval is met when multisig with the `tryExecution` option

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);

        assertEq(plugin.canExecute(pid), true, "Should be true");
        plugin.execute(pid, actions);

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.ProposalExecutionForbidden.selector, pid));
        plugin.execute(pid, actions);

        undoSwitch();
        switchTo(alice);
    }

    function test_ExecuteEmitsEvents() public {
        // emits the `ProposalExecuted` and `ProposalCreated` events

        setTime(10);
        vm.deal(address(dao), 1 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);

        // event
        vm.expectEmit();
        emit Executed(pid);
        vm.expectEmit();
        uint256 targetPid = 10 << 128 | 10 << 64;
        emit ProposalCreated(targetPid, address(plugin), 10, "", actions, 0);
        plugin.execute(pid, actions);

        // 2
        setTime(20);
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        actionsHash = plugin.hashActions(actions);
        pid = plugin.createProposal("ipfs://", actionsHash, optimisticPlugin, false);

        // Alice
        undoSwitch();
        switchTo(alice);
        plugin.approve(pid);

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);

        // events
        vm.expectEmit();
        emit Executed(pid);
        vm.expectEmit();
        targetPid = (20 << 128 | 20 << 64) + 1;
        emit ProposalCreated(targetPid, address(plugin), 20, "ipfs://", actions, 0);
        plugin.execute(pid, actions);
    }

    function test_ExecutesWithEnoughApprovalsOnTime() public {
        // executes if the minimum approval is met

        vm.deal(address(dao), 1 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);
        (bool executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        plugin.execute(pid, actions);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // 2
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";

        actionsHash = plugin.hashActions(actions);
        pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        undoSwitch();
        switchTo(alice);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        plugin.execute(pid, actions);

        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        undoSwitch();
        switchTo(alice);
    }

    function test_ExecuteRevertsWhenTheGivenActionsDontMatchTheHash() public {
        vm.deal(address(dao), 1 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        bytes32 actionsHash = 0; // invalid hash
        uint256 pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);
        (bool executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.InvalidActions.selector, pid));
        plugin.execute(pid, actions);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // 2
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";

        actionsHash = plugin.hashActions(actions);
        pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        undoSwitch();
        switchTo(alice);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Fake actions
        IDAO.Action[] memory otherActions = new IDAO.Action[](1);
        otherActions[0].value = 10000 ether;
        otherActions[0].to = address(carol);
        otherActions[0].data = hex"44556677";
        vm.expectRevert(abi.encodeWithSelector(EmergencyMultisig.InvalidActions.selector, pid));
        plugin.execute(pid, otherActions);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // With ok actions
        plugin.execute(pid, actions);

        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        undoSwitch();
        switchTo(alice);
    }

    function test_ExecuteWhenPassedAndCalledByAnyoneWithTheActions() public {
        // executes if the minimum approval is met and can be called by an unlisted accounts

        vm.deal(address(dao), 4 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);
        (bool executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        undoSwitch();
        switchTo(randomWallet);
        plugin.execute(pid, actions);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // 2
        undoSwitch();
        switchTo(alice);

        actions = new IDAO.Action[](1);
        actions[0].value = 3 ether;
        actions[0].to = address(carol);
        actions[0].data = hex"0011223344556677";
        actionsHash = plugin.hashActions(actions);
        pid = plugin.createProposal("", actionsHash, optimisticPlugin, false);

        // Alice
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);
        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        undoSwitch();
        switchTo(randomWallet);
        plugin.execute(pid, actions);

        (executed,,,,,) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        undoSwitch();
        switchTo(alice);
    }

    function test_GetProposalReturnsTheRightValues() public {
        // Get proposal returns the right values

        setTime(10);
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        bytes32 actionsHash = plugin.hashActions(actions);
        uint256 pid = plugin.createProposal("ipfs://", actionsHash, optimisticPlugin, false);

        (
            bool executed,
            uint16 approvals,
            EmergencyMultisig.ProposalParameters memory parameters,
            bytes memory encryptedPayloadURI,
            bytes32 destinationActionsHash,
            OptimisticTokenVotingPlugin destinationPlugin
        ) = plugin.getProposal(pid);

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
        (dao, plugin,, newOptimisticPlugin) = makeDaoWithEmergencyMultisigAndOptimistic(alice);
        blockForward(1);
        vm.deal(address(dao), 1 ether);

        pid = plugin.createProposal("ipfs://12340000", actionsHash, newOptimisticPlugin, true);

        (executed, approvals, parameters, encryptedPayloadURI, destinationActionsHash, destinationPlugin) =
            plugin.getProposal(pid);

        assertEq(executed, false);
        assertEq(approvals, 1);
        assertEq(parameters.minApprovals, 3);
        assertEq(parameters.snapshotBlock, block.number - 1);
        assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(encryptedPayloadURI, "ipfs://12340000");
        assertEq(destinationActionsHash, actionsHash);
        assertEq(address(destinationPlugin), address(newOptimisticPlugin));

        // 3 approve
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);

        (executed, approvals, parameters, encryptedPayloadURI, destinationActionsHash, destinationPlugin) =
            plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 3);
        assertEq(parameters.snapshotBlock, block.number - 1);
        assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(encryptedPayloadURI, "ipfs://12340000");
        assertEq(destinationActionsHash, actionsHash);
        assertEq(address(destinationPlugin), address(newOptimisticPlugin));

        // Execute
        undoSwitch();
        switchTo(alice);
        dao.grant(address(newOptimisticPlugin), address(plugin), newOptimisticPlugin.PROPOSER_PERMISSION_ID());
        plugin.execute(pid, actions);

        // 4 execute
        (executed, approvals, parameters, encryptedPayloadURI, destinationActionsHash, destinationPlugin) =
            plugin.getProposal(pid);

        assertEq(executed, true, "Should be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 3);
        assertEq(parameters.snapshotBlock, block.number - 1);
        assertEq(parameters.expirationDate, block.timestamp + EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD);
        assertEq(encryptedPayloadURI, "ipfs://12340000");
        assertEq(destinationActionsHash, actionsHash);
        assertEq(address(destinationPlugin), address(newOptimisticPlugin));
    }

    function test_ProxiedProposalHasTheSameSettingsAsTheOriginal() public {
        // Recreated proposal has the same settings and actions as registered here

        bool open;
        bool executed;
        OptimisticTokenVotingPlugin.ProposalParameters memory parameters;
        uint256 vetoTally;
        IDAO.Action[] memory retrievedActions;
        uint256 allowFailureMap;

        setTime(10);

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
        bytes32 actionsHash = plugin.hashActions(submittedActions);
        uint256 pid = plugin.createProposal("ipfs://metadata", actionsHash, optimisticPlugin, false);

        // Approve
        plugin.approve(pid);
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);

        undoSwitch();
        switchTo(alice);
        plugin.execute(pid, submittedActions);

        // Check round
        uint256 targetPid = (uint256(block.timestamp) << 128 | uint256(block.timestamp) << 64);
        (open, executed, parameters, vetoTally, retrievedActions, allowFailureMap) =
            optimisticPlugin.getProposal(targetPid);

        assertEq(open, false, "Should not be open");
        assertEq(executed, true, "Should be executed");
        assertEq(vetoTally, 0, "Should be 0");

        assertEq(parameters.vetoEndDate, block.timestamp, "Incorrect vetoEndDate");

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

        submittedActions = new IDAO.Action[](2);
        submittedActions[1].to = address(dao);
        submittedActions[1].value = 0;
        submittedActions[1].data = abi.encodeWithSelector(DAO.daoURI.selector);
        submittedActions[0].to = address(multisig);
        submittedActions[0].value = 0;
        submittedActions[0].data = abi.encodeWithSelector(Addresslist.addresslistLength.selector);
        actionsHash = plugin.hashActions(submittedActions);
        pid = plugin.createProposal("ipfs://more-metadata", actionsHash, optimisticPlugin, false);

        // Approve
        plugin.approve(pid);
        undoSwitch();
        switchTo(bob);
        plugin.approve(pid);
        undoSwitch();
        switchTo(carol);
        plugin.approve(pid);

        undoSwitch();
        switchTo(alice);
        plugin.execute(pid, submittedActions);

        // Check round
        targetPid = (uint256(block.timestamp) << 128 | uint256(block.timestamp) << 64) + 1;
        (open, executed, parameters, vetoTally, retrievedActions, allowFailureMap) =
            optimisticPlugin.getProposal(targetPid);

        assertEq(open, false, "Should not be open");
        assertEq(executed, true, "Should be executed");
        assertEq(vetoTally, 0, "Should be 0");

        assertEq(parameters.vetoEndDate, 10, "Incorrect vetoEndDate");

        assertEq(retrievedActions.length, 2, "Should be 2");

        assertEq(retrievedActions[1].to, address(dao), "Incorrect to");
        assertEq(retrievedActions[1].value, 0, "Incorrect value");
        assertEq(retrievedActions[1].data, abi.encodeWithSelector(DAO.daoURI.selector), "Incorrect data");
        assertEq(retrievedActions[0].to, address(multisig), "Incorrect to");
        assertEq(retrievedActions[0].value, 0, "Incorrect value");
        assertEq(
            retrievedActions[0].data, abi.encodeWithSelector(Addresslist.addresslistLength.selector), "Incorrect data"
        );

        assertEq(allowFailureMap, 0, "Should be 0");
    }

    // Upgrade plugin

    function test_UpgradeToRevertsWhenCalledFromNonUpgrader() public {
        address _newImplementation = address(new EmergencyMultisig());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), alice, plugin.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );

        plugin.upgradeTo(_newImplementation);

        assertEq(plugin.implementation(), address(EMERGENCY_MULTISIG_BASE));
    }

    function test_UpgradeToAndCallRevertsWhenCalledFromNonUpgrader() public {
        dao.grant(address(plugin), alice, plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());
        address _newImplementation = address(new EmergencyMultisig());

        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: multisig});

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), alice, plugin.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );
        plugin.upgradeToAndCall(
            _newImplementation, abi.encodeCall(EmergencyMultisig.updateMultisigSettings, (settings))
        );

        assertEq(plugin.implementation(), address(EMERGENCY_MULTISIG_BASE));
    }

    function test_UpgradeToSucceedsWhenCalledFromUpgrader() public {
        dao.grant(address(plugin), alice, plugin.UPGRADE_PLUGIN_PERMISSION_ID());

        address _newImplementation = address(new EmergencyMultisig());

        vm.expectEmit();
        emit Upgraded(_newImplementation);

        plugin.upgradeTo(_newImplementation);

        assertEq(plugin.implementation(), address(_newImplementation));
    }

    function test_UpgradeToAndCallSucceedsWhenCalledFromUpgrader() public {
        dao.grant(address(plugin), alice, plugin.UPGRADE_PLUGIN_PERMISSION_ID());
        dao.grant(address(plugin), alice, plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID());

        address _newImplementation = address(new EmergencyMultisig());

        vm.expectEmit();
        emit Upgraded(_newImplementation);

        EmergencyMultisig.MultisigSettings memory settings =
            EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: multisig});
        plugin.upgradeToAndCall(
            _newImplementation, abi.encodeCall(EmergencyMultisig.updateMultisigSettings, (settings))
        );

        assertEq(plugin.implementation(), address(_newImplementation));
    }
}
