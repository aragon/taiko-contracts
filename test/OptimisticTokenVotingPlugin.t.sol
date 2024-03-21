// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console2} from "forge-std/Test.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {IOptimisticTokenVoting} from "../src/IOptimisticTokenVoting.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {RATIO_BASE, RatioOutOfBounds} from "@aragon/osx/plugins/utils/Ratio.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {ERC20VotesMock} from "./mocks/ERC20VotesMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

contract OptimisticTokenVotingPluginTest is Test {
    address immutable daoBase = address(new DAO());
    address immutable pluginBase = address(new OptimisticTokenVotingPlugin());
    address immutable votingTokenBase = address(new ERC20VotesMock());

    DAO public dao;
    OptimisticTokenVotingPlugin public plugin;
    ERC20VotesMock votingToken;

    address alice = address(0xa11ce);
    address bob = address(0xB0B);
    address randomWallet = vm.addr(1234567890);
    OptimisticTokenVotingPlugin.BridgeSettings lzAppEndpoint =
        OptimisticTokenVotingPlugin.BridgeSettings(
            1,
            address(0xb41d5e),
            address(0x1f1d5e)
        );

    // Events from external contracts
    event Initialized(uint8 version);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        IDAO.Action[] actions,
        uint256 allowFailureMap
    );
    event VetoCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint256 votingPower
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event OptimisticGovernanceSettingsUpdated(
        uint32 minVetoRatio,
        uint64 minDuration,
        uint256 minProposerVotingPower
    );
    event Upgraded(address indexed implementation);

    function setUp() public {
        vm.startPrank(alice);

        // Deploy a DAO with Alice as root
        dao = DAO(
            payable(
                createProxyAndCall(
                    address(daoBase),
                    abi.encodeWithSelector(
                        DAO.initialize.selector,
                        "",
                        alice,
                        address(0x0),
                        ""
                    )
                )
            )
        );

        // Deploy ERC20 token
        votingToken = ERC20VotesMock(
            createProxyAndCall(
                address(votingTokenBase),
                abi.encodeWithSelector(ERC20VotesMock.initialize.selector)
            )
        );
        votingToken.mint(alice, 10 ether);
        votingToken.delegate(alice);
        vm.roll(block.number + 1);

        // Deploy a new plugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 10 days,
                    minProposerVotingPower: 0
                });

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );

        // The plugin can execute on the DAO
        dao.grant(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());

        // Alice can create proposals on the plugin
        dao.grant(address(plugin), alice, plugin.PROPOSER_PERMISSION_ID());
    }

    // Initialize
    function test_InitializeRevertsIfInitialized() public {
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 10 days,
                    minProposerVotingPower: 0
                });

        vm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        plugin.initialize(dao, settings, votingToken, lzAppEndpoint);
    }

    function test_InitializeSetsTheProperValues() public {
        // Initial settings
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 10 days,
                    minProposerVotingPower: 0
                });
        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );
        assertEq(
            plugin.minVetoRatio(),
            uint32(RATIO_BASE / 10),
            "Incorrect minVetoRatio"
        );
        assertEq(plugin.minDuration(), 10 days, "Incorrect minDuration");
        assertEq(
            plugin.minProposerVotingPower(),
            0,
            "Incorrect minProposerVotingPower"
        );

        // Different minVetoRatio
        settings.minVetoRatio = uint32(RATIO_BASE / 5);
        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );
        assertEq(
            plugin.minVetoRatio(),
            uint32(RATIO_BASE / 5),
            "Incorrect minVetoRatio"
        );

        // Different minDuration
        settings.minDuration = 25 days;
        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );
        assertEq(plugin.minDuration(), 25 days, "Incorrect minDuration");

        // A token with 10 eth supply
        votingToken = ERC20VotesMock(
            createProxyAndCall(
                address(votingTokenBase),
                abi.encodeWithSelector(ERC20VotesMock.initialize.selector)
            )
        );
        votingToken.mint(alice, 10 ether);
        vm.roll(block.number + 5);

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );

        // Different minProposerVotingPower
        settings.minProposerVotingPower = 1 ether;
        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );
        assertEq(
            plugin.minProposerVotingPower(),
            1 ether,
            "Incorrect minProposerVotingPower"
        );
    }

    function test_InitializeEmitsEvent() public {
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 10 days,
                    minProposerVotingPower: 0
                });

        vm.expectEmit();
        emit Initialized(uint8(1));

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );
    }

    // Getters
    function test_SupportsOptimisticGovernanceInterface() public {
        bool supported = plugin.supportsInterface(
            plugin.OPTIMISTIC_GOVERNANCE_INTERFACE_ID()
        );
        assertEq(
            supported,
            true,
            "Should support OPTIMISTIC_GOVERNANCE_INTERFACE_ID"
        );
    }

    function test_SupportsIOptimisticTokenVotingInterface() public {
        bool supported = plugin.supportsInterface(
            type(IOptimisticTokenVoting).interfaceId
        );
        assertEq(supported, true, "Should support IOptimisticTokenVoting");
    }

    function test_SupportsIMembershipInterface() public {
        bool supported = plugin.supportsInterface(
            type(IMembership).interfaceId
        );
        assertEq(supported, true, "Should support IMembership");
    }

    function test_SupportsIProposalInterface() public {
        bool supported = plugin.supportsInterface(type(IProposal).interfaceId);
        assertEq(supported, true, "Should support IProposal");
    }

    function test_SupportsIERC165UpgradeableInterface() public {
        bool supported = plugin.supportsInterface(
            type(IERC165Upgradeable).interfaceId
        );
        assertEq(supported, true, "Should support IERC165Upgradeable");
    }

    function testFuzz_SupportsInterfaceReturnsFalseOtherwise(
        bytes4 _randomInterfaceId
    ) public {
        bool supported = plugin.supportsInterface(bytes4(0x000000));
        assertEq(supported, false, "Should not support any other interface");

        supported = plugin.supportsInterface(bytes4(0xffffffff));
        assertEq(supported, false, "Should not support any other interface");

        supported = plugin.supportsInterface(_randomInterfaceId);
        assertEq(supported, false, "Should not support any other interface");
    }

    function test_GetVotingTokenReturnsTheRightAddress() public {
        assertEq(
            address(plugin.getVotingToken()),
            address(votingToken),
            "Incorrect voting token"
        );

        address oldToken = address(plugin.getVotingToken());

        // New token
        votingToken = ERC20VotesMock(
            createProxyAndCall(
                address(votingTokenBase),
                abi.encodeWithSelector(ERC20VotesMock.initialize.selector)
            )
        );

        // Deploy a new plugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 10 days,
                    minProposerVotingPower: 0
                });

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );

        assertEq(
            address(plugin.getVotingToken()),
            address(votingToken),
            "Incorrect voting token"
        );
        assertEq(
            address(votingToken) != oldToken,
            true,
            "The token address sould have changed"
        );
    }

    function test_MinVetoRatioReturnsTheRightValue() public {
        assertEq(
            plugin.minVetoRatio(),
            uint32(RATIO_BASE / 10),
            "Incorrect minVetoRatio"
        );

        // New plugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 5),
                    minDuration: 10 days,
                    minProposerVotingPower: 0
                });

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );

        assertEq(
            plugin.minVetoRatio(),
            uint32(RATIO_BASE / 5),
            "Incorrect minVetoRatio"
        );
    }

    function test_MinDurationReturnsTheRightValue() public {
        assertEq(plugin.minDuration(), 10 days, "Incorrect minDuration");

        // New plugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 5),
                    minDuration: 25 days,
                    minProposerVotingPower: 0
                });

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );

        assertEq(plugin.minDuration(), 25 days, "Incorrect minDuration");
    }

    function test_MinProposerVotingPowerReturnsTheRightValue() public {
        assertEq(
            plugin.minProposerVotingPower(),
            0,
            "Incorrect minProposerVotingPower"
        );

        // New token
        votingToken = ERC20VotesMock(
            createProxyAndCall(
                address(votingTokenBase),
                abi.encodeWithSelector(ERC20VotesMock.initialize.selector)
            )
        );
        votingToken.mint(alice, 10 ether);
        vm.roll(block.number + 1);

        // Deploy a new plugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 10 days,
                    minProposerVotingPower: 1 ether
                });

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );

        assertEq(
            plugin.minProposerVotingPower(),
            1 ether,
            "Incorrect minProposerVotingPower"
        );
    }

    function test_TokenHoldersAreMembers() public {
        assertEq(plugin.isMember(alice), true, "Alice should not be a member");
        assertEq(plugin.isMember(bob), false, "Bob should not be a member");
        assertEq(
            plugin.isMember(randomWallet),
            false,
            "Random wallet should not be a member"
        );

        // New token
        votingToken = ERC20VotesMock(
            createProxyAndCall(
                address(votingTokenBase),
                abi.encodeWithSelector(ERC20VotesMock.initialize.selector)
            )
        );
        votingToken.mint(alice, 10 ether);
        votingToken.mint(bob, 5 ether);
        vm.roll(block.number + 1);

        // Deploy a new plugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 10 days,
                    minProposerVotingPower: 1 ether
                });

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );

        assertEq(plugin.isMember(alice), true, "Alice should be a member");
        assertEq(plugin.isMember(bob), true, "Bob should be a member");
        assertEq(
            plugin.isMember(randomWallet),
            false,
            "Random wallet should not be a member"
        );
    }

    // Create proposal
    function test_CreateProposalRevertsWhenCalledByANonProposer() public {
        vm.stopPrank();
        vm.startPrank(bob);
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                bob,
                plugin.PROPOSER_PERMISSION_ID()
            )
        );
        plugin.createProposal("", actions, 0, 0, 0);

        vm.stopPrank();
        vm.startPrank(alice);

        plugin.createProposal("", actions, 0, 0, 0);
    }

    function test_CreateProposalSucceedsWhenMinimumVotingPowerIsZero() public {
        // Bob can create proposals on the plugin now
        dao.grant(address(plugin), bob, plugin.PROPOSER_PERMISSION_ID());

        vm.stopPrank();
        vm.startPrank(bob);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal("", actions, 0, 0, 0);
        assertEq(proposalId, 0);
        proposalId = plugin.createProposal("", actions, 0, 0, 0);
        assertEq(proposalId, 1);
    }

    function test_CreateProposalRevertsWhenTheCallerOwnsLessThanTheMinimumVotingPower()
        public
    {
        vm.stopPrank();
        vm.startPrank(alice);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory newSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 10 days,
                    minProposerVotingPower: 5 ether
                });
        dao.grant(address(plugin), bob, plugin.PROPOSER_PERMISSION_ID());
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);

        vm.stopPrank();
        vm.startPrank(bob);

        // Bob holds no tokens
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalCreationForbidden.selector,
                bob
            )
        );
        plugin.createProposal("", actions, 0, 0, 0);
    }

    function test_CreateProposalRevertsIfThereIsNoVotingPower() public {
        vm.stopPrank();
        vm.startPrank(alice);

        // Deploy ERC20 token (0 supply)
        votingToken = ERC20VotesMock(
            createProxyAndCall(
                address(votingTokenBase),
                abi.encodeWithSelector(ERC20VotesMock.initialize.selector)
            )
        );

        // Deploy a new plugin instance
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 10 days,
                    minProposerVotingPower: 0
                });
        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );
        dao.grant(address(plugin), alice, plugin.PROPOSER_PERMISSION_ID());

        // Try to create
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.NoVotingPower.selector
            )
        );
        plugin.createProposal("", actions, 0, 0, 0);
    }

    function test_CreateProposalRevertsIfTheStartDateIsAfterTheEndDate()
        public
    {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint32 startDate = 200000;
        uint32 endDate = 10;
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.DateOutOfBounds.selector,
                startDate + 10 days,
                endDate
            )
        );
        plugin.createProposal("", actions, 0, startDate, endDate);
    }

    function test_CreateProposalRevertsIfStartDateIsInThePast() public {
        vm.warp(10); // timestamp = 10

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.DateOutOfBounds.selector,
                block.timestamp,
                1
            )
        );
        uint32 startDate = 1;
        plugin.createProposal("", actions, 0, startDate, startDate + 10 days);
    }

    function test_CreateProposalRevertsIfEndDateIsEarlierThanMinDuration()
        public
    {
        vm.warp(500); // timestamp = 500

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint32 startDate = 1000;
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.DateOutOfBounds.selector,
                startDate + 10 days,
                startDate + 10 minutes
            )
        );
        plugin.createProposal(
            "",
            actions,
            0,
            startDate,
            startDate + 10 minutes
        );
    }

    function test_CreateProposalStartsNowWhenStartDateIsZero() public {
        vm.warp(500);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint32 startDate = 0;
        uint256 proposalId = plugin.createProposal(
            "",
            actions,
            0,
            startDate,
            0
        );

        (
            ,
            ,
            OptimisticTokenVotingPlugin.ProposalParameters memory parameters,
            ,
            ,

        ) = plugin.getProposal(proposalId);
        assertEq(500, parameters.startDate, "Incorrect startDate");
    }

    function test_CreateProposalEndsAfterMinDurationWhenEndDateIsZero() public {
        vm.warp(500);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint32 startDate = 0;
        uint32 endDate = 0;
        uint256 proposalId = plugin.createProposal(
            "",
            actions,
            0,
            startDate,
            endDate
        );

        (
            ,
            ,
            OptimisticTokenVotingPlugin.ProposalParameters memory parameters,
            ,
            ,

        ) = plugin.getProposal(proposalId);
        assertEq(500 + 10 days, parameters.endDate, "Incorrect endDate");
    }

    function test_CreateProposalUsesTheCurrentMinVetoRatio() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal("", actions, 0, 0, 0);

        (
            ,
            ,
            OptimisticTokenVotingPlugin.ProposalParameters memory parameters,
            ,
            ,

        ) = plugin.getProposal(proposalId);
        assertEq(
            parameters.minVetoVotingPower,
            1 ether,
            "Incorrect minVetoVotingPower"
        );

        // Now with a different value
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 5),
                    minDuration: 10 days,
                    minProposerVotingPower: 0
                });
        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );

        dao.grant(address(plugin), alice, plugin.PROPOSER_PERMISSION_ID());
        proposalId = plugin.createProposal("", actions, 0, 0, 0);
        (, , parameters, , , ) = plugin.getProposal(proposalId);
        assertEq(
            parameters.minVetoVotingPower,
            2 ether,
            "Incorrect minVetoVotingPower"
        );
    }

    function test_CreateProposalReturnsTheProposalId() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal("", actions, 0, 0, 0);
        assertEq(proposalId == 0, true, "Should have created proposal 0");

        proposalId = plugin.createProposal("", actions, 0, 0, 0);
        assertEq(proposalId == 1, true, "Should have created proposal 1");
    }

    function test_CreateProposalEmitsAnEvent() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectEmit();
        emit ProposalCreated(
            0,
            alice,
            uint64(block.timestamp),
            uint64(block.timestamp + 10 days),
            "",
            actions,
            0
        );
        plugin.createProposal("", actions, 0, 0, 0);
    }

    // Can Veto
    function test_CanVetoReturnsFalseWhenAProposalDoesntExist() public {
        vm.roll(10);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal("ipfs://", actions, 0, 0, 0);
        vm.roll(20);

        assertEq(
            plugin.canVeto(proposalId, alice),
            true,
            "Alice should be able to veto"
        );

        // non existing
        assertEq(
            plugin.canVeto(proposalId + 200, alice),
            false,
            "Alice should not be able to veto on non existing proposals"
        );
    }

    function test_CanVetoReturnsFalseWhenAProposalHasNotStarted() public {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );

        // Unstarted
        assertEq(
            plugin.canVeto(proposalId, alice),
            false,
            "Alice should not be able to veto"
        );

        // Started
        vm.warp(startDate + 1);
        assertEq(
            plugin.canVeto(proposalId, alice),
            true,
            "Alice should be able to veto"
        );
    }

    function test_CanVetoReturnsFalseWhenAVoterAlreadyVetoed() public {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );
        vm.warp(startDate + 1);

        plugin.veto(proposalId);

        assertEq(
            plugin.canVeto(proposalId, alice),
            false,
            "Alice should not be able to veto"
        );
    }

    function test_CanVetoReturnsFalseWhenAVoterAlreadyEnded() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );
        vm.warp(endDate + 1);

        assertEq(
            plugin.canVeto(proposalId, alice),
            false,
            "Alice should not be able to veto"
        );
    }

    function test_CanVetoReturnsFalseWhenNoVotingPower() public {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );

        vm.warp(startDate + 1);

        // Alice owns tokens
        assertEq(
            plugin.canVeto(proposalId, alice),
            true,
            "Alice should be able to veto"
        );

        // Bob owns no tokens
        assertEq(
            plugin.canVeto(proposalId, bob),
            false,
            "Bob should not be able to veto"
        );
    }

    function test_CanVetoReturnsTrueOtherwise() public {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );
        vm.warp(startDate + 1);

        assertEq(
            plugin.canVeto(proposalId, alice),
            true,
            "Alice should be able to veto"
        );
    }

    // Veto
    function test_VetoRevertsWhenAProposalDoesntExist() public {
        vm.roll(10);
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );
        vm.roll(20);

        // non existing
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector,
                proposalId + 200,
                alice
            )
        );
        plugin.veto(proposalId + 200);
    }

    function test_VetoRevertsWhenAProposalHasNotStarted() public {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );

        // Unstarted
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector,
                proposalId,
                alice
            )
        );
        plugin.veto(proposalId);
        assertEq(
            plugin.hasVetoed(proposalId, alice),
            false,
            "Alice should not have vetoed"
        );

        // Started
        vm.warp(startDate + 1);
        plugin.veto(proposalId);
        assertEq(
            plugin.hasVetoed(proposalId, alice),
            true,
            "Alice should have vetoed"
        );
    }

    function test_VetoRevertsWhenAVoterAlreadyVetoed() public {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );
        vm.warp(startDate + 1);

        assertEq(
            plugin.hasVetoed(proposalId, alice),
            false,
            "Alice should not have vetoed"
        );
        plugin.veto(proposalId);
        assertEq(
            plugin.hasVetoed(proposalId, alice),
            true,
            "Alice should have vetoed"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector,
                proposalId,
                alice
            )
        );
        plugin.veto(proposalId);
        assertEq(
            plugin.hasVetoed(proposalId, alice),
            true,
            "Alice should have vetoed"
        );
    }

    function test_VetoRevertsWhenAVoterAlreadyEnded() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );
        vm.warp(endDate + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector,
                proposalId,
                alice
            )
        );
        plugin.veto(proposalId);
        assertEq(
            plugin.hasVetoed(proposalId, alice),
            false,
            "Alice should not have vetoed"
        );
    }

    function test_VetoRevertsWhenNoVotingPower() public {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );

        vm.warp(startDate + 1);

        vm.stopPrank();
        vm.startPrank(bob);

        // Bob owns no tokens
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector,
                proposalId,
                bob
            )
        );
        plugin.veto(proposalId);
        assertEq(
            plugin.hasVetoed(proposalId, bob),
            false,
            "Bob should not have vetoed"
        );

        vm.stopPrank();
        vm.startPrank(alice);

        // Alice owns tokens
        plugin.veto(proposalId);
        assertEq(
            plugin.hasVetoed(proposalId, alice),
            true,
            "Alice should have vetoed"
        );
    }

    function test_VetoRegistersAVetoForTheTokenHolderAndIncreasesTheTally()
        public
    {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );
        vm.warp(startDate + 1);

        (, , , uint256 tally1, , ) = plugin.getProposal(proposalId);
        assertEq(tally1, 0, "Tally should be zero");

        plugin.veto(proposalId);
        assertEq(
            plugin.hasVetoed(proposalId, alice),
            true,
            "Alice should have vetoed"
        );

        (, , , uint256 tally2, , ) = plugin.getProposal(proposalId);
        assertEq(tally2, 10 ether, "Tally should be 10 eth");
    }

    function test_VetoEmitsAnEvent() public {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );
        vm.warp(startDate + 1);

        vm.expectEmit();
        emit VetoCast(proposalId, alice, 10 ether);
        plugin.veto(proposalId);
    }

    // Has vetoed
    function test_HasVetoedReturnsTheRightValues() public {
        uint64 startDate = 50;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            0
        );
        vm.warp(startDate + 1);

        assertEq(
            plugin.hasVetoed(proposalId, alice),
            false,
            "Alice should not have vetoed"
        );
        plugin.veto(proposalId);
        assertEq(
            plugin.hasVetoed(proposalId, alice),
            true,
            "Alice should have vetoed"
        );
    }

    // Can execute
    function test_CanExecuteReturnsFalseWhenNotEnded() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        assertEq(
            plugin.canExecute(proposalId),
            false,
            "The proposal shouldn't be executable"
        );

        vm.warp(startDate + 1);

        assertEq(
            plugin.canExecute(proposalId),
            false,
            "The proposal shouldn't be executable"
        );
        plugin.veto(proposalId);

        assertEq(
            plugin.canExecute(proposalId),
            false,
            "The proposal shouldn't be executable yet"
        );
    }

    function test_CanExecuteReturnsFalseWhenDefeated() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        assertEq(
            plugin.canExecute(proposalId),
            false,
            "The proposal shouldn't be executable"
        );

        vm.warp(startDate + 1);

        plugin.veto(proposalId);
        assertEq(
            plugin.canExecute(proposalId),
            false,
            "The proposal shouldn't be executable yet"
        );

        vm.warp(endDate + 1);

        assertEq(
            plugin.canExecute(proposalId),
            false,
            "The proposal shouldn't be executable"
        );
    }

    function test_CanExecuteReturnsFalseWhenAlreadyExecuted() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        vm.warp(endDate + 1);
        assertEq(
            plugin.canExecute(proposalId),
            true,
            "The proposal should be executable"
        );

        plugin.execute(proposalId);

        assertEq(
            plugin.canExecute(proposalId),
            false,
            "The proposal shouldn't be executable"
        );
    }

    function test_CanExecuteReturnsTrueOtherwise() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        assertEq(
            plugin.canExecute(proposalId),
            false,
            "The proposal shouldn't be executable"
        );

        vm.warp(startDate + 1);

        assertEq(
            plugin.canExecute(proposalId),
            false,
            "The proposal shouldn't be executable yet"
        );

        vm.warp(endDate + 1);

        assertEq(
            plugin.canExecute(proposalId),
            true,
            "The proposal should be executable"
        );
    }

    // Veto threshold reached
    function test_IsMinVetoRatioReachedReturnsTheAppropriateValues() public {
        // Deploy ERC20 token
        votingToken = ERC20VotesMock(
            createProxyAndCall(
                address(votingTokenBase),
                abi.encodeWithSelector(ERC20VotesMock.initialize.selector)
            )
        );
        votingToken.mint(alice, 24 ether);
        votingToken.mint(bob, 1 ether);
        votingToken.mint(randomWallet, 75 ether);

        votingToken.delegate(alice);

        vm.stopPrank();
        vm.startPrank(bob);
        votingToken.delegate(bob);

        vm.stopPrank();
        vm.startPrank(randomWallet);
        votingToken.delegate(randomWallet);

        vm.roll(block.number + 1);

        // Deploy a new plugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32((RATIO_BASE * 25) / 100),
                    minDuration: 10 days,
                    minProposerVotingPower: 0
                });

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(pluginBase),
                abi.encodeWithSelector(
                    OptimisticTokenVotingPlugin.initialize.selector,
                    dao,
                    settings,
                    votingToken,
                    lzAppEndpoint
                )
            )
        );

        vm.stopPrank();
        vm.startPrank(alice);

        // Permissions
        dao.grant(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());
        dao.grant(address(plugin), alice, plugin.PROPOSER_PERMISSION_ID());

        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        vm.warp(startDate + 1);

        assertEq(
            plugin.isMinVetoRatioReached(proposalId),
            false,
            "The veto threshold shouldn't be met"
        );
        // Alice vetoes 24%
        plugin.veto(proposalId);

        assertEq(
            plugin.isMinVetoRatioReached(proposalId),
            false,
            "The veto threshold shouldn't be met"
        );

        vm.stopPrank();
        vm.startPrank(bob);

        // Bob vetoes +1% => met
        plugin.veto(proposalId);

        assertEq(
            plugin.isMinVetoRatioReached(proposalId),
            true,
            "The veto threshold should be met"
        );

        vm.stopPrank();
        vm.startPrank(randomWallet);

        // Random wallet vetoes +75% => still met
        plugin.veto(proposalId);

        assertEq(
            plugin.isMinVetoRatioReached(proposalId),
            true,
            "The veto threshold should still be met"
        );
    }

    // Execute
    function test_ExecuteRevertsWhenNotEnded() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector,
                proposalId
            )
        );
        plugin.execute(proposalId);

        vm.warp(startDate + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector,
                proposalId
            )
        );
        plugin.execute(proposalId);

        vm.warp(endDate);
        plugin.execute(proposalId);

        (, bool executed, , , , ) = plugin.getProposal(proposalId);
        assertEq(executed, true, "The proposal should be executed");
    }

    function test_ExecuteRevertsWhenDefeated() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        vm.warp(startDate + 1);

        plugin.veto(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector,
                proposalId
            )
        );
        plugin.execute(proposalId);

        vm.warp(endDate + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector,
                proposalId
            )
        );
        plugin.execute(proposalId);

        (, bool executed, , , , ) = plugin.getProposal(proposalId);
        assertEq(executed, false, "The proposal should not be executed");
    }

    function test_ExecuteRevertsWhenAlreadyExecuted() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        vm.warp(endDate + 1);

        plugin.execute(proposalId);

        (, bool executed1, , , , ) = plugin.getProposal(proposalId);
        assertEq(executed1, true, "The proposal should be executed");

        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector,
                proposalId
            )
        );
        plugin.execute(proposalId);

        (, bool executed2, , , , ) = plugin.getProposal(proposalId);
        assertEq(executed2, true, "The proposal should be executed");
    }

    function test_ExecuteSucceedsOtherwise() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        vm.warp(endDate + 1);

        plugin.execute(proposalId);
    }

    function test_ExecuteMarksTheProposalAsExecuted() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        vm.warp(endDate + 1);

        plugin.execute(proposalId);

        (, bool executed2, , , , ) = plugin.getProposal(proposalId);
        assertEq(executed2, true, "The proposal should be executed");
    }

    function test_ExecuteEmitsAnEvent() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        vm.warp(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = plugin.createProposal(
            "ipfs://",
            actions,
            0,
            startDate,
            endDate
        );

        vm.warp(endDate + 1);

        vm.expectEmit();
        emit ProposalExecuted(proposalId);
        plugin.execute(proposalId);
    }

    // Update settings
    function test_UpdateOptimisticGovernanceSettingsRevertsWhenNoPermission()
        public
    {
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory newSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 5),
                    minDuration: 15 days,
                    minProposerVotingPower: 1 ether
                });
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                alice,
                plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
            )
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);

        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        plugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsRevertsWhenTheMinVetoRatioIsZero()
        public
    {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory newSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: 0,
                    minDuration: 10 days,
                    minProposerVotingPower: 0 ether
                });
        vm.expectRevert(
            abi.encodeWithSelector(RatioOutOfBounds.selector, 1, 0)
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsRevertsWhenTheMinVetoRatioIsAboveTheMaximum()
        public
    {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory newSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE + 1),
                    minDuration: 10 days,
                    minProposerVotingPower: 0 ether
                });
        vm.expectRevert(
            abi.encodeWithSelector(
                RatioOutOfBounds.selector,
                RATIO_BASE,
                uint32(RATIO_BASE + 1)
            )
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsRevertsWhenTheMinDurationIsLessThanFourDays()
        public
    {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory newSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 4 days - 1,
                    minProposerVotingPower: 0 ether
                });
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector,
                4 days,
                4 days - 1
            )
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);

        // 2
        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 hours,
            minProposerVotingPower: 0 ether
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector,
                4 days,
                10 hours
            )
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);

        // 3
        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 0,
            minProposerVotingPower: 0 ether
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector,
                4 days,
                0
            )
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsRevertsWhenTheMinDurationIsMoreThanOneYear()
        public
    {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory newSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 10),
                    minDuration: 365 days + 1,
                    minProposerVotingPower: 0 ether
                });
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector,
                365 days,
                365 days + 1
            )
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);

        // 2
        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 500 days,
            minProposerVotingPower: 0 ether
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector,
                365 days,
                500 days
            )
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);

        // 3
        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 1000 days,
            minProposerVotingPower: 0 ether
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector,
                365 days,
                1000 days
            )
        );
        plugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsEmitsAnEventWhenSuccessful()
        public
    {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory newSettings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 5),
                    minDuration: 15 days,
                    minProposerVotingPower: 1 ether
                });

        vm.expectEmit();
        emit OptimisticGovernanceSettingsUpdated({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 15 days,
            minProposerVotingPower: 1 ether
        });

        plugin.updateOptimisticGovernanceSettings(newSettings);
    }

    // Upgrade plugin
    function test_UpgradeToRevertsWhenCalledFromNonUpgrader() public {
        address _pluginBase = address(new OptimisticTokenVotingPlugin());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                alice,
                plugin.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );

        plugin.upgradeTo(_pluginBase);
    }

    function test_UpgradeToAndCallRevertsWhenCalledFromNonUpgrader() public {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        address _pluginBase = address(new OptimisticTokenVotingPlugin());

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 5),
                    minDuration: 15 days,
                    minProposerVotingPower: 1 ether
                });

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                alice,
                plugin.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );

        plugin.upgradeToAndCall(
            _pluginBase,
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin
                    .updateOptimisticGovernanceSettings
                    .selector,
                settings
            )
        );
    }

    function test_UpgradeToSucceedsWhenCalledFromUpgrader() public {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPGRADE_PLUGIN_PERMISSION_ID()
        );

        address _pluginBase = address(new OptimisticTokenVotingPlugin());

        vm.expectEmit();
        emit Upgraded(_pluginBase);

        plugin.upgradeTo(_pluginBase);
    }

    function test_UpgradeToAndCallSucceedsWhenCalledFromUpgrader() public {
        dao.grant(
            address(plugin),
            alice,
            plugin.UPGRADE_PLUGIN_PERMISSION_ID()
        );
        dao.grant(
            address(plugin),
            alice,
            plugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        address _pluginBase = address(new OptimisticTokenVotingPlugin());

        vm.expectEmit();
        emit Upgraded(_pluginBase);

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
            memory settings = OptimisticTokenVotingPlugin
                .OptimisticGovernanceSettings({
                    minVetoRatio: uint32(RATIO_BASE / 5),
                    minDuration: 15 days,
                    minProposerVotingPower: 1 ether
                });
        plugin.upgradeToAndCall(
            _pluginBase,
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin
                    .updateOptimisticGovernanceSettings
                    .selector,
                settings
            )
        );
    }

    // HELPERS
    function createProxyAndCall(
        address _logic,
        bytes memory _data
    ) private returns (address) {
        return address(new ERC1967Proxy(_logic, _data));
    }
}
