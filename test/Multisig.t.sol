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

contract MultisigTest is Test {
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

    // Events/errors to be tested here (duplicate)
    event MultisigSettingsUpdated(bool onlyListed, uint16 indexed minApprovals);
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
    event ProposalExecuted(uint256 indexed proposalId);

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
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                1,
                0
            )
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                3,
                2
            )
        );
        plugin.removeAddresses(addrs);

        // ko
        addrs[0] = carol;
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                3,
                2
            )
        );
        plugin.removeAddresses(addrs);

        // ko
        addrs[0] = david;
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                3,
                2
            )
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        plugin.addAddresses(addrs);

        // 1
        addrs[0] = alice;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        plugin.addAddresses(addrs);

        // 2
        addrs[0] = bob;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        plugin.addAddresses(addrs);

        // 3
        addrs[0] = carol;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        plugin.addAddresses(addrs);

        // 4
        addrs[0] = david;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        plugin.addAddresses(addrs);

        // ok
        addrs[0] = vm.addr(1234);
        plugin.removeAddresses(addrs);

        // ko
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        plugin.removeAddresses(addrs);

        addrs[0] = vm.addr(2345);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        plugin.removeAddresses(addrs);

        addrs[0] = vm.addr(3456);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        plugin.removeAddresses(addrs);

        addrs[0] = vm.addr(4567);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        plugin.removeAddresses(addrs);

        addrs[0] = randomWallet;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
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
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 5 // More than 4
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                4,
                5
            )
        );
        plugin.updateMultisigSettings(settings);

        // More signers

        address[] memory signers = new address[](1);
        signers[0] = randomWallet;
        plugin.addAddresses(signers);

        // should not fail now
        plugin.updateMultisigSettings(settings);

        // More than that, should fail again
        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 6 // More than 5
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                5,
                6
            )
        );
        plugin.updateMultisigSettings(settings);
    }

    // PROPOSAL CREATION

    function test_IncrementsTheProposalCounter() public {
        // increments the proposal counter
        vm.roll(block.number + 1);

        assertEq(plugin.proposalCount(), 0, "Should have no proposals");

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            0,
            uint64(block.timestamp + 500)
        );

        assertEq(plugin.proposalCount(), 1, "Should have 1 proposal");

        // 2
        plugin.createProposal(
            "ipfs://",
            actions,
            0,
            true,
            true,
            0,
            uint64(block.timestamp + 500)
        );

        assertEq(plugin.proposalCount(), 2, "Should have 2 proposals");
    }

    function test_CreatesAndReturnsUniqueProposalIds() public {
        // creates unique proposal IDs for each proposal
        vm.roll(block.number + 1);

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            0,
            uint64(block.timestamp + 500)
        );

        assertEq(pid, 0, "Should be 0");

        // 2
        pid = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            true,
            true,
            0,
            uint64(block.timestamp + 500)
        );

        assertEq(pid, 1, "Should be 1");

        // 2
        pid = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            true,
            true,
            0,
            uint64(block.timestamp + 500)
        );

        assertEq(pid, 2, "Should be 2");
    }

    function test_EmitsProposalCreated() public {
        // emits the `ProposalCreated` event
        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectEmit();
        emit ProposalCreated({
            proposalId: 0,
            creator: alice,
            metadata: "",
            startDate: uint64(block.timestamp),
            endDate: uint64(block.timestamp) + 500,
            actions: actions,
            allowFailureMap: 0
        });
        plugin.createProposal(
            "",
            actions,
            0,
            true,
            true,
            0,
            uint64(block.timestamp + 500)
        );

        // 2
        vm.stopPrank();
        vm.startPrank(bob);
        vm.roll(block.number + 1);

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
            startDate: uint64(block.timestamp) + 10,
            endDate: uint64(block.timestamp) + 1000,
            actions: actions,
            allowFailureMap: 255
        });
        plugin.createProposal(
            "ipfs://",
            actions,
            255,
            false,
            false,
            uint64(block.timestamp + 10),
            uint64(block.timestamp + 1000)
        );

        // undo
        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_RevertsIfSettingsChangedInSameBlock() public {
        // reverts if the multisig settings have been changed in the same block

        // 1
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalCreationForbidden.selector,
                alice
            )
        );
        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            0,
            uint64(block.timestamp + 10)
        );

        // Next block
        vm.roll(block.number + 1);
        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            0,
            uint64(block.timestamp + 10)
        );
    }

    function test_CreatesWhenUnlistedAccountsAllowed() public {
        // creates a proposal when unlisted accounts are allowed

        // Deploy a new multisig instance
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: false,
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

        vm.stopPrank();
        vm.startPrank(randomWallet);
        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            0,
            uint64(block.timestamp + 10)
        );

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_RevertsWhenOnlyListedAndAnotherWalletCreates() public {
        // reverts if the user is not on the list and only listed accounts can create proposals

        vm.stopPrank();
        vm.startPrank(randomWallet);
        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalCreationForbidden.selector,
                randomWallet
            )
        );
        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            0,
            uint64(block.timestamp + 10)
        );

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_RevertsWhenSenderWasListedBeforeButNotNow() public {
        // reverts if `_msgSender` is not listed before although she was listed in the last block

        // Deploy a new multisig instance
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });
        address[] memory addrs = new address[](1);
        addrs[0] = alice;

        plugin = Multisig(
            createProxyAndCall(
                address(multisigBase),
                abi.encodeCall(Multisig.initialize, (dao, addrs, settings))
            )
        );
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );
        vm.roll(block.number + 1);

        // Add+remove
        addrs[0] = bob;
        plugin.addAddresses(addrs);

        addrs[0] = alice;
        plugin.removeAddresses(addrs);

        // Alice cannot create now
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalCreationForbidden.selector,
                alice
            )
        );
        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            0,
            uint64(block.timestamp + 10)
        );

        // Bob can create now
        vm.stopPrank();
        vm.startPrank(bob);

        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            0,
            uint64(block.timestamp + 10)
        );

        assertEq(plugin.isListed(alice), false, "Should not be listed");
        assertEq(plugin.isListed(bob), true, "Should be listed");
    }

    function test_CreatesProposalWithoutApprovingIfUnspecified() public {
        // creates a proposal successfully and does not approve if not specified

        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal(
            "",
            actions,
            0,
            false, // approveProposal
            false,
            0,
            uint64(block.timestamp + 10)
        );

        assertEq(
            plugin.hasApproved(pid, alice),
            false,
            "Should not have approved"
        );

        plugin.approve(pid, false);

        assertEq(plugin.hasApproved(pid, alice), true, "Should have approved");
    }

    function test_CreatesAndApprovesWhenSpecified() public {
        // creates a proposal successfully and approves if specified

        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal(
            "",
            actions,
            0,
            true, // approveProposal
            false,
            0,
            uint64(block.timestamp + 10)
        );
        assertEq(plugin.hasApproved(pid, alice), true, "Should have approved");
    }

    function test_ShouldRevertWhenStartDateLessThanNow() public {
        // should revert if startDate is < than now

        vm.roll(block.number + 1);
        vm.warp(10); // timestamp = 10

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, 10, 5)
        );
        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            5, // startDate = 5, now = 10
            uint64(block.timestamp + 100)
        );

        // 2
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, 10, 9)
        );
        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            9, // startDate = 9, now = 10
            uint64(block.timestamp + 100)
        );

        // ok
        plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            10, // startDate = 10, now = 10
            uint64(block.timestamp + 100)
        );
    }

    function test_ShouldRevertIfEndDateBeforeStartDate() public {
        // should revert if endDate is < than startDate

        vm.roll(block.number + 1);
        vm.warp(10); // timestamp = 10

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, 20, 15)
        );
        plugin.createProposal("", actions, 0, false, false, 20, 15);

        // 2
        vm.expectRevert(
            abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, 20, 19)
        );
        plugin.createProposal("", actions, 0, false, false, 20, 19);

        // ok
        plugin.createProposal("", actions, 0, false, false, 20, 20);
        plugin.createProposal("", actions, 0, false, false, 20, 30);
        plugin.createProposal("", actions, 0, false, false, 20, 100);
    }

    // CAN APPROVE

    function testFuzz_CanApproveReturnsfFalseIfNotListed(
        address _randomWallet
    ) public {
        // returns `false` if the approver is not listed

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 1});
            address[] memory signers = new address[](1);
            signers[0] = alice;

            plugin = Multisig(
                createProxyAndCall(
                    address(multisigBase),
                    abi.encodeCall(
                        Multisig.initialize,
                        (dao, signers, settings)
                    )
                )
            );
            vm.roll(block.number + 1);
        }

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // ko
        if (_randomWallet != alice) {
            assertEq(
                plugin.canApprove(pid, _randomWallet),
                false,
                "Should be false"
            );
        }

        // static ko
        assertEq(
            plugin.canApprove(pid, randomWallet),
            false,
            "Should be false"
        );

        // static ok
        assertEq(plugin.canApprove(pid, alice), true, "Should be true");
    }

    function test_CanApproveReturnsFalseIfApproved() public {
        // returns `false` if the approver has already approved
        {
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 4});
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

        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        assertEq(plugin.canApprove(pid, alice), true, "Should be true");
        plugin.approve(pid, false);
        assertEq(plugin.canApprove(pid, alice), false, "Should be false");

        // Bob
        assertEq(plugin.canApprove(pid, bob), true, "Should be true");
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        assertEq(plugin.canApprove(pid, bob), false, "Should be false");

        // Carol
        assertEq(plugin.canApprove(pid, carol), true, "Should be true");
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);
        assertEq(plugin.canApprove(pid, carol), false, "Should be false");

        // David
        assertEq(plugin.canApprove(pid, david), true, "Should be true");
        vm.stopPrank();
        vm.startPrank(david);
        plugin.approve(pid, false);
        assertEq(plugin.canApprove(pid, david), false, "Should be false");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_CanApproveReturnsFalseIfUnstarted() public {
        // returns `false` if the proposal hasn't started yet

        vm.roll(block.number + 1);
        vm.warp(0); // timestamp = 0

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            uint64(block.timestamp) + 1,
            100
        );

        assertEq(plugin.canApprove(pid, alice), false, "Should be false");

        // forward
        vm.warp(block.timestamp + 1);
        assertEq(plugin.canApprove(pid, alice), true, "Should be true");
    }

    function test_CanApproveReturnsFalseIfExpired() public {
        // returns `false` if the proposal has ended

        vm.roll(block.number + 1);
        vm.warp(10); // timestamp = 10

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 10, 100);

        assertEq(plugin.canApprove(pid, alice), true, "Should be true");

        vm.warp(101); // timestamp = 101

        assertEq(plugin.canApprove(pid, alice), false, "Should be false");
    }

    function test_CanApproveReturnsFalseIfExecuted() public {
        // returns `false` if the proposal is already executed

        vm.skip(true); // TODO:

        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );

        vm.roll(block.number + 1);

        bool executed;
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, false);

        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);

        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, true); // auto execute

        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // David cannot approve
        assertEq(plugin.canApprove(pid, david), false, "Should be false");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_CanApproveReturnsTrueIfListed() public {
        // returns `true` if the approver is listed

        vm.roll(block.number + 1);
        vm.warp(10); // timestamp = 10

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        assertEq(plugin.canApprove(pid, alice), true, "Should be true");
        assertEq(plugin.canApprove(pid, bob), true, "Should be true");
        assertEq(plugin.canApprove(pid, carol), true, "Should be true");
        assertEq(plugin.canApprove(pid, david), true, "Should be true");

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: false, minApprovals: 1});
            address[] memory signers = new address[](1);
            signers[0] = randomWallet;

            plugin = Multisig(
                createProxyAndCall(
                    address(multisigBase),
                    abi.encodeCall(
                        Multisig.initialize,
                        (dao, signers, settings)
                    )
                )
            );
            vm.roll(block.number + 1);
        }

        // now ko
        actions = new IDAO.Action[](0);
        pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

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

        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        assertEq(plugin.hasApproved(pid, alice), false, "Should be false");
        assertEq(plugin.hasApproved(pid, bob), false, "Should be false");
        assertEq(plugin.hasApproved(pid, carol), false, "Should be false");
        assertEq(plugin.hasApproved(pid, david), false, "Should be false");
    }

    function test_HasApprovedReturnsTrueWhenUserApproved() public {
        // returns `true` if user has approved

        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        assertEq(plugin.hasApproved(pid, alice), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.hasApproved(pid, alice), true, "Should be true");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        assertEq(plugin.hasApproved(pid, bob), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.hasApproved(pid, bob), true, "Should be true");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        assertEq(plugin.hasApproved(pid, carol), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.hasApproved(pid, carol), true, "Should be true");

        // David
        vm.stopPrank();
        vm.startPrank(david);
        assertEq(plugin.hasApproved(pid, david), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.hasApproved(pid, david), true, "Should be true");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_ApproveRevertsIfApprovingMultipleTimes() public {
        // reverts when approving multiple times

        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ApprovalCastForbidden.selector,
                pid,
                alice
            )
        );
        plugin.approve(pid, true);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ApprovalCastForbidden.selector,
                pid,
                bob
            )
        );
        plugin.approve(pid, false);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ApprovalCastForbidden.selector,
                pid,
                carol
            )
        );
        plugin.approve(pid, true);

        vm.stopPrank();
        vm.startPrank(alice);
    }

    // APPROVE

    function test_ApprovesWithTheSenderAddress() public {
        // approves with the msg.sender address
        // Same as test_HasApprovedReturnsTrueWhenUserApproved()

        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        assertEq(plugin.hasApproved(pid, alice), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.hasApproved(pid, alice), true, "Should be true");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        assertEq(plugin.hasApproved(pid, bob), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.hasApproved(pid, bob), true, "Should be true");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        assertEq(plugin.hasApproved(pid, carol), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.hasApproved(pid, carol), true, "Should be true");

        // David
        vm.stopPrank();
        vm.startPrank(david);
        assertEq(plugin.hasApproved(pid, david), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.hasApproved(pid, david), true, "Should be true");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_ApproveRevertsIfUnstarted() public {
        // reverts if the proposal hasn't started yet

        vm.roll(block.number + 1);
        vm.warp(0); // timestamp = 0

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            uint64(block.timestamp) + 1, // future
            100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ApprovalCastForbidden.selector,
                pid,
                alice
            )
        );
        plugin.approve(pid, false);

        // forward
        vm.warp(block.timestamp + 1);
        plugin.approve(pid, false);

        // 2
        pid = plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            uint64(block.timestamp) + 1, // future
            100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ApprovalCastForbidden.selector,
                pid,
                alice
            )
        );
        plugin.approve(pid, true);

        // forward
        vm.warp(block.timestamp + 1);
        plugin.approve(pid, true);
    }

    function test_ApproveRevertsIfExpired() public {
        // reverts if the proposal has ended

        vm.roll(block.number + 1);
        vm.warp(10); // timestamp = 10

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 10, 100);

        assertEq(plugin.canApprove(pid, alice), true, "Should be true");

        vm.warp(101); // timestamp = 101
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ApprovalCastForbidden.selector,
                pid,
                alice
            )
        );
        plugin.approve(pid, false);

        vm.warp(200); // timestamp = 200
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ApprovalCastForbidden.selector,
                pid,
                alice
            )
        );
        plugin.approve(pid, false);

        // 2
        vm.warp(10); // timestamp = 10
        pid = plugin.createProposal("", actions, 0, false, false, 10, 100);

        assertEq(plugin.canApprove(pid, alice), true, "Should be true");

        vm.warp(101); // timestamp = 101
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ApprovalCastForbidden.selector,
                pid,
                alice
            )
        );
        plugin.approve(pid, true);

        vm.warp(200); // timestamp = 200
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ApprovalCastForbidden.selector,
                pid,
                alice
            )
        );
        plugin.approve(pid, true);
    }

    function test_ApprovingProposalsEmits() public {
        // Approving a proposal emits the Approved event

        vm.roll(block.number + 1);
        vm.warp(10); // timestamp = 10

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 10, 100);

        vm.expectEmit();
        emit Approved(pid, alice);
        plugin.approve(pid, false);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectEmit();
        emit Approved(pid, bob);
        plugin.approve(pid, false);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        vm.expectEmit();
        emit Approved(pid, carol);
        plugin.approve(pid, false);

        // David (even if it already passed)
        vm.stopPrank();
        vm.startPrank(david);
        vm.expectEmit();
        emit Approved(pid, david);
        plugin.approve(pid, false);

        vm.stopPrank();
        vm.startPrank(alice);
    }

    // CAN EXECUTE

    function test_CanExecuteReturnsFalseIfBelowMinApprovals() public {
        // returns `false` if the proposal has not reached the minimum approvals yet

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 2});
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
            dao.grant(
                address(optimisticPlugin),
                address(plugin),
                optimisticPlugin.PROPOSER_PERMISSION_ID()
            );
            vm.roll(block.number + 1);
        }
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        vm.stopPrank();
        vm.startPrank(alice);

        // More approvals required (4)

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 4});
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
            dao.grant(
                address(optimisticPlugin),
                address(plugin),
                optimisticPlugin.PROPOSER_PERMISSION_ID()
            );
            vm.roll(block.number + 1);
        }

        pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        vm.stopPrank();
        vm.startPrank(alice);
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // David
        vm.stopPrank();
        vm.startPrank(david);
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_CanExecuteReturnsFalseIfUnstarted() public {
        // returns `false` if the proposal hasn't started yet

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 1});
            address[] memory signers = new address[](1);
            signers[0] = alice;

            plugin = Multisig(
                createProxyAndCall(
                    address(multisigBase),
                    abi.encodeCall(
                        Multisig.initialize,
                        (dao, signers, settings)
                    )
                )
            );
            vm.roll(block.number + 1);
        }

        vm.warp(0); // timestamp = 0

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            uint64(block.timestamp) + 1, // future
            100
        );

        assertEq(plugin.canExecute(pid), false, "Should be false");

        // forward
        vm.warp(block.timestamp + 1);
        assertEq(plugin.canExecute(pid), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        // 2
        pid = plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            uint64(block.timestamp) + 1, // future
            100
        );
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // forward
        vm.warp(block.timestamp + 1);
        assertEq(plugin.canExecute(pid), false, "Should be false");
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), true, "Should be true");
    }

    function test_CanExecuteReturnsFalseIfExpired() public {
        // returns `false` if the proposal has ended

        vm.roll(block.number + 1);

        // 1
        vm.warp(0); // timestamp = 0

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        vm.warp(101); // timestamp = 101

        assertEq(plugin.canExecute(pid), false, "Should be false");

        // 2
        vm.warp(0); // timestamp = 0

        actions = new IDAO.Action[](0);
        pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        plugin.approve(pid, false);
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        vm.warp(101); // timestamp = 101

        assertEq(plugin.canExecute(pid), false, "Should be false");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_CanExecuteReturnsFalseIfExecuted() public {
        // returns `false` if the proposal is already executed

        vm.skip(true); // TODO:

        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );
        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, false);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);

        assertEq(plugin.canExecute(pid), true, "Should be true");
        plugin.execute(pid);

        assertEq(plugin.canExecute(pid), false, "Should be false");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_CanExecuteReturnsTrueWhenAllGood() public {
        // returns `true` if the proposal can be executed

        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Alice
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), false, "Should be false");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);

        assertEq(plugin.canExecute(pid), true, "Should be true");
    }

    // EXECUTE

    function test_ExecuteRevertsIfBelowMinApprovals() public {
        // reverts if minApprovals is not met yet

        vm.skip(true); // TODO:

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 2});
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
            dao.grant(
                address(optimisticPlugin),
                address(plugin),
                optimisticPlugin.PROPOSER_PERMISSION_ID()
            );
            vm.roll(block.number + 1);
        }
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        plugin.execute(pid); // ok

        // More approvals required (4)

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 4});
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
            dao.grant(
                address(optimisticPlugin),
                address(plugin),
                optimisticPlugin.PROPOSER_PERMISSION_ID()
            );
            vm.roll(block.number + 1);
        }

        pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        vm.stopPrank();
        vm.startPrank(alice);
        plugin.approve(pid, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        // David
        vm.stopPrank();
        vm.startPrank(david);
        plugin.approve(pid, false);
        plugin.execute(pid);

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_ExecuteRevertsIfUnstarted() public {
        // reverts if the proposal hasn't started yet

        vm.skip(true); // TODO:

        vm.roll(block.number + 1);
        vm.warp(0); // timestamp = 0

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            uint64(block.timestamp) + 1, // future
            100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        // forward
        vm.warp(block.timestamp + 1);
        plugin.approve(pid, false);
        plugin.execute(pid);

        // 2
        pid = plugin.createProposal(
            "",
            actions,
            0,
            false,
            false,
            uint64(block.timestamp) + 1, // future
            100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        // forward
        vm.warp(block.timestamp + 1);
        plugin.approve(pid, true);
        plugin.execute(pid);
    }

    function test_ExecuteRevertsIfExpired() public {
        // reverts if the proposal has expired

        vm.roll(block.number + 1);

        // 1
        vm.warp(0); // timestamp = 0

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        plugin.approve(pid, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        vm.warp(101); // timestamp = 101

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        // 2
        vm.warp(0); // timestamp = 0

        actions = new IDAO.Action[](0);
        pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        plugin.approve(pid, false);
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);
        assertEq(plugin.canExecute(pid), true, "Should be true");

        vm.warp(101); // timestamp = 101

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_ExecuteRevertsWhenAlreadyExecuted() public {
        // executes if the minimum approval is met when multisig with the `tryExecution` option

        vm.skip(true); // TODO:

        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );
        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, false);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);

        assertEq(plugin.canExecute(pid), true, "Should be true");
        plugin.execute(pid);

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.ProposalExecutionForbidden.selector,
                pid
            )
        );
        plugin.execute(pid);

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_ExecuteEmitsEvents() public {
        // emits the `ProposalExecuted` and `ProposalCreated` events

        vm.skip(true);

        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );
        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, false);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);

        // event
        vm.expectEmit();
        emit ProposalExecuted(pid);
        plugin.execute(pid);

        // 2
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        pid = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            false,
            false,
            0,
            100
        );

        // Alice
        plugin.approve(pid, false);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);

        // events
        vm.expectEmit();
        emit ProposalCreated(
            0,
            alice,
            uint64(block.timestamp),
            100,
            "ipfs://",
            actions,
            0
        );
        plugin.execute(pid);
    }

    function test_ExecutesWhenApprovingWithTryExecutionAndEnoughApprovals()
        public
    {
        // executes if the minimum approval is met when multisig with the `tryExecution` option

        vm.skip(true); // TODO:

        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);
        (bool executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Alice
        plugin.approve(pid, true);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, true);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, true);

        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_ExecuteEmitsWhenAutoExecutedFromApprove() public {
        // emits the `Approved`, `ProposalExecuted`, and `ProposalCreated` events if execute is called inside the `approve` method

        vm.skip(true);

        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );
        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, true);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, true);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        vm.expectEmit();
        emit ProposalExecuted(pid);
        plugin.approve(pid, true);

        // 2
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        pid = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            false,
            false,
            0,
            100
        );

        // Alice
        plugin.approve(pid, true);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, true);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        vm.expectEmit();
        emit Approved(pid, carol);
        plugin.approve(pid, true);

        // 3
        actions = new IDAO.Action[](1);
        actions[0].value = 5 ether;
        actions[0].to = address(carol);
        actions[0].data = hex"44556677";
        pid = plugin.createProposal(
            "ipfs://...",
            actions,
            255,
            false,
            false,
            0,
            100
        );

        // Alice
        plugin.approve(pid, true);

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, true);

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        vm.expectEmit();
        emit ProposalCreated(
            2, // foreign pid
            address(plugin),
            uint64(block.timestamp),
            100,
            "ipfs://...",
            actions,
            255
        );
        plugin.approve(pid, true);

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_ExecutesWithEnoughApprovalsOnTime() public {
        // executes if the minimum approval is met

        vm.skip(true);

        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );
        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, false);
        (bool executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        plugin.execute(pid);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // 2
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        pid = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            false,
            false,
            0,
            100
        );

        // Alice
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        plugin.execute(pid);

        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_ExecuteWhenPassedAndCalledByAnyone() public {
        // executes if the minimum approval is met and can be called by an unlisted accounts

        vm.skip(true); // TODO:

        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );
        vm.roll(block.number + 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint pid = plugin.createProposal("", actions, 0, false, false, 0, 100);

        // Alice
        plugin.approve(pid, false);
        (bool executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        vm.stopPrank();
        vm.startPrank(randomWallet);
        plugin.execute(pid);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        // 2
        actions = new IDAO.Action[](1);
        actions[0].value = 1 ether;
        actions[0].to = address(bob);
        actions[0].data = hex"00112233";
        pid = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            false,
            false,
            0,
            100
        );

        // Alice
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Bob
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        // Carol
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);
        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, false, "Should not be executed");

        vm.stopPrank();
        vm.startPrank(randomWallet);
        plugin.execute(pid);

        (executed, , , , ) = plugin.getProposal(pid);
        assertEq(executed, true, "Should be executed");

        vm.stopPrank();
        vm.startPrank(alice);
    }

    function test_GetProposalReturnsTheRightValues() public {
        // Get proposal returns the right values

        vm.skip(true); // TODO:

        bool executed;
        uint16 approvals;
        Multisig.ProposalParameters memory parameters;
        IDAO.Action[] memory actions;
        uint256 allowFailureMap;

        vm.roll(block.number + 1);
        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );
        vm.warp(0); // timestamp = 0

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

        uint pid = plugin.createProposal(
            "ipfs://metadata",
            createActions,
            0,
            false,
            false,
            0,
            500
        );

        // Check round 1
        (executed, approvals, parameters, actions, allowFailureMap) = plugin
            .getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 0, "Should be 0");

        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(
            parameters.snapshotBlock,
            block.number,
            "Incorrect snapshotBlock"
        );
        assertEq(parameters.startDate, block.timestamp, "Incorrect startDate");
        assertEq(parameters.endDate, 500, "Incorrect endDate");

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

        // Approve
        plugin.approve(pid, false);

        // Check round 2
        (executed, approvals, parameters, actions, allowFailureMap) = plugin
            .getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 1, "Should be 1");

        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(
            parameters.snapshotBlock,
            block.number,
            "Incorrect snapshotBlock"
        );
        assertEq(parameters.startDate, block.timestamp, "Incorrect startDate");
        assertEq(parameters.endDate, 500, "Incorrect endDate");

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

        // Approve
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);

        // Check round 3
        (executed, approvals, parameters, actions, allowFailureMap) = plugin
            .getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(
            parameters.snapshotBlock,
            block.number,
            "Incorrect snapshotBlock"
        );
        assertEq(parameters.startDate, block.timestamp, "Incorrect startDate");
        assertEq(parameters.endDate, 500, "Incorrect endDate");

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

        // Execute
        vm.stopPrank();
        vm.startPrank(alice);
        plugin.execute(pid);

        // Check round 4
        (executed, approvals, parameters, actions, allowFailureMap) = plugin
            .getProposal(pid);

        assertEq(executed, true, "Should be executed");
        assertEq(approvals, 3, "Should be 3");

        assertEq(parameters.minApprovals, 3, "Incorrect minApprovals");
        assertEq(
            parameters.snapshotBlock,
            block.number,
            "Incorrect snapshotBlock"
        );
        assertEq(parameters.startDate, block.timestamp, "Incorrect startDate");
        assertEq(parameters.endDate, 500, "Incorrect endDate");

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

        // New proposal, new settings
        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 2});
            address[] memory signers = new address[](3);
            signers[0] = alice;
            signers[1] = bob;
            signers[2] = carol;

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
        createActions = new IDAO.Action[](2);
        createActions[1].to = alice;
        createActions[1].value = 1 ether;
        createActions[1].data = hex"001122334455";
        createActions[0].to = carol;
        createActions[0].value = 3 ether;
        createActions[0].data = hex"223344556677";

        pid = plugin.createProposal(
            "ipfs://different-metadata",
            createActions,
            255,
            true,
            true,
            50,
            550
        );

        // Check round 1
        (executed, approvals, parameters, actions, allowFailureMap) = plugin
            .getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 0, "Should be 0");

        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(
            parameters.snapshotBlock,
            block.number,
            "Incorrect snapshotBlock"
        );
        assertEq(parameters.startDate, 50, "Incorrect startDate");
        assertEq(parameters.endDate, 550, "Incorrect endDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(allowFailureMap, 255, "Should be 255");

        // Approve
        vm.warp(55);
        plugin.approve(pid, false);

        // Check round 2
        (executed, approvals, parameters, actions, allowFailureMap) = plugin
            .getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 1, "Should be 1");

        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(
            parameters.snapshotBlock,
            block.number,
            "Incorrect snapshotBlock"
        );
        assertEq(parameters.startDate, 50, "Incorrect startDate");
        assertEq(parameters.endDate, 550, "Incorrect endDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(allowFailureMap, 255, "Should be 255");

        // Approve
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);

        // Check round 3
        (executed, approvals, parameters, actions, allowFailureMap) = plugin
            .getProposal(pid);

        assertEq(executed, false, "Should not be executed");
        assertEq(approvals, 2, "Should be 2");

        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(
            parameters.snapshotBlock,
            block.number,
            "Incorrect snapshotBlock"
        );
        assertEq(parameters.startDate, 50, "Incorrect startDate");
        assertEq(parameters.endDate, 550, "Incorrect endDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(allowFailureMap, 255, "Should be 255");

        // Execute
        vm.stopPrank();
        vm.startPrank(alice);
        plugin.execute(pid);

        // Check round 4
        (executed, approvals, parameters, actions, allowFailureMap) = plugin
            .getProposal(pid);

        assertEq(executed, true, "Should be executed");
        assertEq(approvals, 2, "Should be 2");

        assertEq(parameters.minApprovals, 2, "Incorrect minApprovals");
        assertEq(
            parameters.snapshotBlock,
            block.number,
            "Incorrect snapshotBlock"
        );
        assertEq(parameters.startDate, 50, "Incorrect startDate");
        assertEq(parameters.endDate, 550, "Incorrect endDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(allowFailureMap, 255, "Should be 255");
    }

    function test_ProxiedProposalHasTheSameSettingsAsTheOriginal() public {
        // Recreated proposal has the same settings and actions as registered here

        vm.skip(true); // TODO:

        bool open;
        bool executed;
        OptimisticTokenVotingPlugin.ProposalParameters memory parameters;
        uint256 vetoTally;
        IDAO.Action[] memory actions;
        uint256 allowFailureMap;

        vm.roll(block.number + 1);
        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );
        vm.warp(0); // timestamp = 0

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

        uint pid = plugin.createProposal(
            "ipfs://metadata",
            createActions,
            0,
            false,
            false,
            0,
            500
        );

        // Approve
        plugin.approve(pid, false);
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);

        vm.stopPrank();
        vm.startPrank(alice);
        plugin.execute(pid);

        // Check round
        (
            open,
            executed,
            parameters,
            vetoTally,
            actions,
            allowFailureMap
        ) = optimisticPlugin.getProposal(pid);

        assertEq(open, true, "Should be open");
        assertEq(executed, false, "Should not be executed");
        assertEq(vetoTally, 0, "Should be 0");

        assertEq(parameters.startDate, block.timestamp, "Incorrect startDate");
        assertEq(parameters.endDate, 500, "Incorrect endDate");

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

        createActions = new IDAO.Action[](2);
        createActions[1].to = alice;
        createActions[1].value = 1 ether;
        createActions[1].data = hex"001122334455";
        createActions[0].to = carol;
        createActions[0].value = 3 ether;
        createActions[0].data = hex"223344556677";

        pid = plugin.createProposal(
            "ipfs://more-metadata",
            createActions,
            255,
            false,
            false,
            50,
            550
        );

        // Approve
        plugin.approve(pid, false);
        vm.stopPrank();
        vm.startPrank(bob);
        plugin.approve(pid, false);
        vm.stopPrank();
        vm.startPrank(carol);
        plugin.approve(pid, false);

        vm.stopPrank();
        vm.startPrank(alice);
        plugin.execute(pid);

        // Check round
        (
            open,
            executed,
            parameters,
            vetoTally,
            actions,
            allowFailureMap
        ) = optimisticPlugin.getProposal(pid);

        assertEq(open, false, "Should not be open");
        assertEq(executed, false, "Should not be executed");
        assertEq(vetoTally, 0, "Should be 0");

        assertEq(parameters.startDate, 50, "Incorrect startDate");
        assertEq(parameters.endDate, 550, "Incorrect endDate");

        assertEq(actions.length, 2, "Should be 2");

        assertEq(actions[1].to, alice, "Incorrect to");
        assertEq(actions[1].value, 1 ether, "Incorrect value");
        assertEq(actions[1].data, hex"001122334455", "Incorrect data");
        assertEq(actions[0].to, carol, "Incorrect to");
        assertEq(actions[0].value, 3 ether, "Incorrect value");
        assertEq(actions[0].data, hex"223344556677", "Incorrect data");

        assertEq(allowFailureMap, 255, "Should be 255");
    }
}
