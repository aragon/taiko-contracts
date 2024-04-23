// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
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
import {ERC20VotesMock} from "./mocks/ERC20VotesMock.sol";
import {RATIO_BASE, RatioOutOfBounds} from "@aragon/osx/plugins/utils/Ratio.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {createProxyAndCall} from "./common.sol";

contract StandardProposalConditionTest is Test {
    address immutable daoBase = address(new DAO());
    address immutable multisigBase = address(new Multisig());
    address immutable optimisticBase =
        address(new OptimisticTokenVotingPlugin());
    address immutable votingTokenBase = address(new ERC20VotesMock());

    address immutable alice = address(0xa11ce);
    address immutable bob = address(0xB0B);
    address immutable carol = address(0xc4601);
    address immutable david = address(0xd471d);
    address immutable randomWallet = vm.addr(1234567890);

    DAO dao;
    Multisig plugin;
    OptimisticTokenVotingPlugin optimisticPlugin;

    string metadataURI = "ipfs://1234";

    // Events to be tested here (duplicate)
    event MultisigSettingsUpdated(bool onlyListed, uint16 indexed minApprovals);
    event MembersAdded(address[] members);
    event MembersRemoved(address[] members);

    function setUp() public {
        vm.startPrank(alice);

        // Deploy a DAO with Alice as root
        dao = DAO(
            payable(
                createProxyAndCall(
                    address(daoBase),
                    abi.encodeCall(
                        DAO.initialize,
                        ("", alice, address(0x0), "")
                    )
                )
            )
        );

        {
            // Deploy ERC20 token
            ERC20VotesMock votingToken = ERC20VotesMock(
                createProxyAndCall(
                    address(votingTokenBase),
                    abi.encodeCall(ERC20VotesMock.initialize, ())
                )
            );
            // Deploy a target contract for passed proposals to be created in
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
                memory targetContractSettings = OptimisticTokenVotingPlugin
                    .OptimisticGovernanceSettings({
                        minVetoRatio: uint32(RATIO_BASE / 10),
                        minDuration: 10 days,
                        minProposerVotingPower: 0
                    });

            optimisticPlugin = OptimisticTokenVotingPlugin(
                createProxyAndCall(
                    address(optimisticBase),
                    abi.encodeCall(
                        OptimisticTokenVotingPlugin.initialize,
                        (dao, targetContractSettings, votingToken)
                    )
                )
            );
        }

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 3});
            address[] memory signers = new address[](4);
            signers[0] = alice;
            signers[1] = bob;
            signers[2] = carol;
            signers[3] = david;

            plugin = Multisig(
                createProxyAndCall(
                    address(multisigBase),
                    abi.encodeCall(
                        Multisig.initialize,
                        (dao, signers, settings)
                    )
                )
            );
        }

        // // The Multisig can create proposals on the Optimistic plugin
        // dao.grant(
        //     address(optimisticPlugin),
        //     address(plugin),
        //     optimisticPlugin.PROPOSER_PERMISSION_ID()
        // );
    }

    function test_RevertsIfTryingToReinitializa() public {
        // Deploy a new multisig instance
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3
        });
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        // Reinitialize should fail
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize(dao, signers, settings);
    }

    function test_AddsInitialAddresses() public {
        // Deploy with 4 signers
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3
        });
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(plugin.isListed(alice), true, "Should be a member");
        assertEq(plugin.isListed(bob), true, "Should be a member");
        assertEq(plugin.isListed(carol), true, "Should be a member");
        assertEq(plugin.isListed(david), true, "Should be a member");

        // Redeploy with just 2 signers
        settings.minApprovals = 1;

        signers = new address[](2);
        signers[0] = alice;
        signers[1] = bob;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(plugin.isListed(alice), true, "Should be a member");
        assertEq(plugin.isListed(bob), true, "Should be a member");
        assertEq(plugin.isListed(carol), false, "Should not be a member");
        assertEq(plugin.isListed(david), false, "Should not be a member");
    }

    function test_ShouldSetMinApprovals() public {
        // 2
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2
        });
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        (, uint16 minApprovals) = plugin.multisigSettings();
        assertEq(minApprovals, uint16(2), "Incorrect minApprovals");

        // Redeploy with 1
        settings.minApprovals = 1;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        (, minApprovals) = plugin.multisigSettings();
        assertEq(minApprovals, uint16(1), "Incorrect minApprovals");
    }

    function test_ShouldSetOnlyListed() public {
        // Deploy with true
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3
        });
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        (bool onlyListed, ) = plugin.multisigSettings();
        assertEq(onlyListed, true, "Incorrect onlyListed");

        // Redeploy with false
        settings.onlyListed = false;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        (onlyListed, ) = plugin.multisigSettings();
        assertEq(onlyListed, false, "Incorrect onlyListed");
    }

    function test_ShouldEmitMultisigSettingsUpdatedOnInstall() public {
        // Deploy with true/3
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3
        });
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, uint16(3));

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        // Deploy with false/2
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 2
        });
        vm.expectEmit();
        emit MultisigSettingsUpdated(false, uint16(2));

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );
    }

    function test_ShouldRevertIfMembersListIsTooLong() public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 3
        });
        address[] memory signers = new address[](65537);

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.AddresslistLengthOutOfBounds.selector,
                65535,
                65537
            )
        );
        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );
    }

    // INTERFACES

    function test_DoesntSupportTheEmptyInterface() public view {
        bool supported = plugin.supportsInterface(0);
        assertEq(supported, false, "Should not support the empty interface");
    }

    function test_SupportsIERC165Upgradeable() public view {
        bool supported = plugin.supportsInterface(
            type(IERC165Upgradeable).interfaceId
        );
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
        bool supported = plugin.supportsInterface(
            type(IMembership).interfaceId
        );
        assertEq(supported, true, "Should support IMembership");
    }

    function test_SupportsAddresslist() public view {
        bool supported = plugin.supportsInterface(
            type(Addresslist).interfaceId
        );
        assertEq(supported, true, "Should support Addresslist");
    }

    function test_SupportsIMultisig() public view {
        bool supported = plugin.supportsInterface(type(IMultisig).interfaceId);
        assertEq(supported, true, "Should support IMultisig");
    }

    // UPDATE MULTISIG SETTINGS

    function test_ShouldntAllowMinApprovalsHigherThenAddrListLength() public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5 // Greater than 4 members below
        });
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                4,
                5
            )
        );

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        // Retry with onlyListed false
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 6 // Greater than 4 members below
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                4,
                6
            )
        );
        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );
    }

    function test_ShouldntAllowMinApprovalsZero() public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 0
        });
        address[] memory signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                1,
                0
            )
        );

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        // Retry with onlyListed false
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 0
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                1,
                0
            )
        );
        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );
    }

    function test_ShouldEmitMultisigSettingsUpdated() public {
        dao.grant(
            address(plugin),
            address(alice),
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        // 1
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 1);
        plugin.updateMultisigSettings(settings);

        // 2
        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 2
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 2);
        plugin.updateMultisigSettings(settings);

        // 3
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 3
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 3);
        plugin.updateMultisigSettings(settings);

        // 4
        settings = Multisig.MultisigSettings({
            onlyListed: false,
            minApprovals: 4
        });

        vm.expectEmit();
        emit MultisigSettingsUpdated(false, 4);
        plugin.updateMultisigSettings(settings);
    }

    function test_ShouldOnlyAllow_UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        public
    {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });
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

        // Retry with the permission
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        vm.expectEmit();
        emit MultisigSettingsUpdated(true, 1);
        plugin.updateMultisigSettings(settings);
    }

    function test_IsMemberShouldReturnWhenApropriate() public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });
        address[] memory signers = new address[](1);
        signers[0] = alice;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(plugin.isMember(alice), true, "Should be a member");
        assertEq(plugin.isMember(bob), false, "Should not be a member");
        assertEq(plugin.isMember(carol), false, "Should not be a member");
        assertEq(plugin.isMember(david), false, "Should not be a member");

        // More members
        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });
        signers = new address[](3);
        signers[0] = bob;
        signers[1] = carol;
        signers[2] = david;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(plugin.isMember(alice), false, "Should not be a member");
        assertEq(plugin.isMember(bob), true, "Should be a member");
        assertEq(plugin.isMember(carol), true, "Should be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");
    }

    function test_IsMemberIsListedShouldReturnTheSameValue() public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });
        address[] memory signers = new address[](1);
        signers[0] = alice;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(
            plugin.isListed(alice),
            plugin.isMember(alice),
            "isMember isListed should be equal"
        );
        assertEq(
            plugin.isListed(bob),
            plugin.isMember(bob),
            "isMember isListed should be equal"
        );
        assertEq(
            plugin.isListed(carol),
            plugin.isMember(carol),
            "isMember isListed should be equal"
        );
        assertEq(
            plugin.isListed(david),
            plugin.isMember(david),
            "isMember isListed should be equal"
        );

        // More members
        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });
        signers = new address[](3);
        signers[0] = bob;
        signers[1] = carol;
        signers[2] = david;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(
            plugin.isListed(alice),
            plugin.isMember(alice),
            "isMember isListed should be equal"
        );
        assertEq(
            plugin.isListed(bob),
            plugin.isMember(bob),
            "isMember isListed should be equal"
        );
        assertEq(
            plugin.isListed(carol),
            plugin.isMember(carol),
            "isMember isListed should be equal"
        );
        assertEq(
            plugin.isListed(david),
            plugin.isMember(david),
            "isMember isListed should be equal"
        );
    }

    function testFuzz_IsMemberIsFalseByDefault(uint256 _randomEntropy) public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });
        address[] memory signers = new address[](1); // 0x0... would be a member but the chance is negligible

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(plugin.isListed(randomWallet), false, "Should be false");
        assertEq(
            plugin.isListed(
                vm.addr(uint256(keccak256(abi.encodePacked(_randomEntropy))))
            ),
            false,
            "Should be false"
        );
    }

    function test_AddsNewMembersAndEmits() public {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        // No
        assertEq(
            plugin.isMember(randomWallet),
            false,
            "Should not be a member"
        );

        address[] memory addrs = new address[](1);
        addrs[0] = randomWallet;

        vm.expectEmit();
        emit MembersAdded({members: addrs});
        plugin.addAddresses(addrs);

        // Yes
        assertEq(plugin.isMember(randomWallet), true, "Should be a member");

        // Next
        addrs = new address[](3);
        addrs[0] = vm.addr(1234);
        addrs[1] = vm.addr(2345);
        addrs[2] = vm.addr(3456);

        // No
        assertEq(plugin.isMember(addrs[0]), false, "Should not be a member");
        assertEq(plugin.isMember(addrs[1]), false, "Should not be a member");
        assertEq(plugin.isMember(addrs[2]), false, "Should not be a member");

        vm.expectEmit();
        emit MembersAdded({members: addrs});
        plugin.addAddresses(addrs);

        // Yes
        assertEq(plugin.isMember(addrs[0]), true, "Should be a member");
        assertEq(plugin.isMember(addrs[1]), true, "Should be a member");
        assertEq(plugin.isMember(addrs[2]), true, "Should be a member");
    }

    function test_RemovesMembersAndEmits() public {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });
        plugin.updateMultisigSettings(settings);

        // Before
        assertEq(plugin.isMember(alice), true, "Should be a member");
        assertEq(plugin.isMember(bob), true, "Should be a member");
        assertEq(plugin.isMember(carol), true, "Should be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");

        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;

        vm.expectEmit();
        emit MembersRemoved({members: addrs});
        plugin.removeAddresses(addrs);

        // After
        assertEq(plugin.isMember(alice), false, "Should not be a member");
        assertEq(plugin.isMember(bob), false, "Should not be a member");
        assertEq(plugin.isMember(carol), true, "Should be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");

        // Next
        addrs = new address[](3);
        addrs[0] = vm.addr(1234);
        addrs[1] = vm.addr(2345);
        addrs[2] = vm.addr(3456);
        plugin.addAddresses(addrs);

        // Remove
        addrs = new address[](2);
        addrs[0] = carol;
        addrs[1] = david;

        vm.expectEmit();
        emit MembersRemoved({members: addrs});
        plugin.removeAddresses(addrs);

        // Yes
        assertEq(plugin.isMember(carol), false, "Should not be a member");
        assertEq(plugin.isMember(david), false, "Should not be a member");
    }

    function test_ShouldRevertIfEmpty() public {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });
        plugin.updateMultisigSettings(settings);

        // Before
        assertEq(plugin.isMember(alice), true, "Should be a member");
        assertEq(plugin.isMember(bob), true, "Should be a member");
        assertEq(plugin.isMember(carol), true, "Should be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");

        // ok
        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        plugin.removeAddresses(addrs);

        addrs[0] = bob;
        plugin.removeAddresses(addrs);

        addrs[0] = carol;
        plugin.removeAddresses(addrs);

        assertEq(plugin.isMember(alice), false, "Should not be a member");
        assertEq(plugin.isMember(bob), false, "Should not be a member");
        assertEq(plugin.isMember(carol), false, "Should not be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");

        // ko
        addrs[0] = david;
        vm.expectRevert();
        plugin.removeAddresses(addrs);

        // Next
        addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        plugin.addAddresses(addrs);

        // Retry removing David
        addrs = new address[](1);
        addrs[0] = david;

        plugin.removeAddresses(addrs);

        // Yes
        assertEq(plugin.isMember(david), false, "Should not be a member");
    }

    function test_ShouldRevertIfLessThanMinApproval() public {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        // Before
        assertEq(plugin.isMember(alice), true, "Should be a member");
        assertEq(plugin.isMember(bob), true, "Should be a member");
        assertEq(plugin.isMember(carol), true, "Should be a member");
        assertEq(plugin.isMember(david), true, "Should be a member");

        // ok
        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        plugin.removeAddresses(addrs);

        // ko
        addrs[0] = bob;
        vm.expectRevert();
        plugin.removeAddresses(addrs);

        // ko
        addrs[0] = carol;
        vm.expectRevert();
        plugin.removeAddresses(addrs);

        // ko
        addrs[0] = david;
        vm.expectRevert();
        plugin.removeAddresses(addrs);

        // Add and retry removing

        addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        plugin.addAddresses(addrs);

        addrs = new address[](1);
        addrs[0] = bob;
        plugin.removeAddresses(addrs);

        // 2
        addrs = new address[](1);
        addrs[0] = vm.addr(2345);
        plugin.addAddresses(addrs);

        addrs = new address[](1);
        addrs[0] = carol;
        plugin.removeAddresses(addrs);

        // 3
        addrs = new address[](1);
        addrs[0] = vm.addr(3456);
        plugin.addAddresses(addrs);

        addrs = new address[](1);
        addrs[0] = david;
        plugin.removeAddresses(addrs);
    }

    function test_ShouldRevertIfDuplicatingAddresses() public {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        // ok
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        plugin.addAddresses(addrs);

        // ko
        vm.expectRevert();
        plugin.addAddresses(addrs);

        // 1
        addrs[0] = alice;
        vm.expectRevert();
        plugin.addAddresses(addrs);

        // 2
        addrs[0] = bob;
        vm.expectRevert();
        plugin.addAddresses(addrs);

        // 3
        addrs[0] = carol;
        vm.expectRevert();
        plugin.addAddresses(addrs);

        // 4
        addrs[0] = david;
        vm.expectRevert();
        plugin.addAddresses(addrs);

        // ok
        addrs[0] = vm.addr(1234);
        plugin.removeAddresses(addrs);

        // ko
        vm.expectRevert();
        plugin.removeAddresses(addrs);

        addrs[0] = vm.addr(2345);
        vm.expectRevert();
        plugin.removeAddresses(addrs);

        addrs[0] = vm.addr(3456);
        vm.expectRevert();
        plugin.removeAddresses(addrs);

        addrs[0] = vm.addr(4567);
        vm.expectRevert();
        plugin.removeAddresses(addrs);

        addrs[0] = randomWallet;
        vm.expectRevert();
        plugin.removeAddresses(addrs);
    }

    function test_onlyWalletWithPermissionsCanAddRemove() public {
        // ko
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                alice,
                plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
            )
        );
        plugin.addAddresses(addrs);

        // ko
        addrs[0] = alice;
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                alice,
                plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
            )
        );
        plugin.removeAddresses(addrs);

        // Permission
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        // ok
        addrs[0] = vm.addr(1234);
        plugin.addAddresses(addrs);

        addrs[0] = alice;
        plugin.removeAddresses(addrs);
    }

    function test_MinApprovalsBiggerThanTheListReverts() public {
        // MinApprovals should be within the boundaries of the list
        vm.skip(true);
    }

    function test_IncrementsTheProposalCounter() public {
        // increments the proposal counter
        vm.skip(true);
    }

    function test_CreatesUniqueProposalIds() public {
        // creates unique proposal IDs for each proposal
        vm.skip(true);
    }

    function test_EmitsProposalCreated() public {
        // emits the `ProposalCreated` event
        vm.skip(true);
    }

    function test_RevertsIfSettingsChangedInSameBlock() public {
        // reverts if the multisig settings have been changed in the same block
        vm.skip(true);
    }

    function test_CreatesWhenUnlistedAccountsAllowed() public {
        // creates a proposal when unlisted accounts are allowed
        vm.skip(true);
    }

    function test_RevertsWhenOnlyListedAndAnotherWalletCreates() public {
        // reverts if the user is not on the list and only listed accounts can create proposals
        vm.skip(true);
    }

    function test_RevertsWhenSenderWasListedBeforeButNotNow() public {
        // reverts if `_msgSender` is not listed in the current block although he was listed in the last block
        vm.skip(true);
    }

    function test_CreatesProposalWithoutApprovingIfUnspecified() public {
        // creates a proposal successfully and does not approve if not specified
        vm.skip(true);
    }

    function test_CreatesAndApprovesWhenSpecified() public {
        // creates a proposal successfully and approves if specified
        vm.skip(true);
    }

    function test_ShouldRevertWhenStartDateLessThanNow() public {
        // should revert if startDate is < than now
        vm.skip(true);
    }

    function test_ShouldRevertIfEndDateBeforeStartDate() public {
        // should revert if endDate is < than startDate
        vm.skip(true);
    }

    function test_CanApproveReturnsFalseIfExecuted() public {
        // returns `false` if the proposal is already executed
        vm.skip(true);
    }

    function test_CanApproveReturnfFalseIfNotListed() public {
        // returns `false` if the approver is not listed
        vm.skip(true);
    }

    function test_CanApproveReturnsFalseIfApproved() public {
        // returns `false` if the approver has already approved
        vm.skip(true);
    }

    function test_CanApproveReturnsFalseIfUnstarted() public {
        // returns `false` if the proposal hasn't started yet
        vm.skip(true);
    }

    function test_CanApproveReturnsTrueIfListed() public {
        // returns `true` if the approver is listed
        vm.skip(true);
    }

    function test_CanApproveReturnsFalseIfTheProposalExpired() public {
        // returns `false` if the proposal has ended
        vm.skip(true);
    }

    function test_HasApprovedReturnsFalseWhenNotApproved() public {
        // returns `false` if user hasn't approved yet
        vm.skip(true);
    }

    function test_HasApprovedReturnsTrueWhenUserApproved() public {
        // returns `true` if user has approved
        vm.skip(true);
    }

    function test_ApproveRevertsIfApprovingMultipleTimes() public {
        // reverts when approving multiple times
        vm.skip(true);
    }
}
