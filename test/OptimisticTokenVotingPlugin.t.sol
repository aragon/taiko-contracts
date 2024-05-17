// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {IOptimisticTokenVoting} from "../src/interfaces/IOptimisticTokenVoting.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx/core/plugin/IPlugin.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {RATIO_BASE, RatioOutOfBounds} from "@aragon/osx/plugins/utils/Ratio.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {ERC20VotesMock} from "./mocks/ERC20VotesMock.sol";
import {TaikoL1} from "../src/adapted-dependencies/TaikoL1.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IERC1822ProxiableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol";
import {createProxyAndCall} from "./helpers/proxy.sol";

contract OptimisticTokenVotingPluginTest is AragonTest {
    DaoBuilder builder;

    DAO dao;
    OptimisticTokenVotingPlugin optimisticPlugin;
    ERC20VotesMock votingToken;
    TaikoL1 taikoL1;

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
    event VetoCast(uint256 indexed proposalId, address indexed voter, uint256 votingPower);
    event ProposalExecuted(uint256 indexed proposalId);
    event OptimisticGovernanceSettingsUpdated(uint32 minVetoRatio, uint64 minDuration);
    event Upgraded(address indexed implementation);

    function setUp() public {
        switchTo(alice);

        builder = new DaoBuilder();
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.build();
    }

    // Initialize
    function test_InitializeRevertsIfInitialized() public {
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });

        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        optimisticPlugin.initialize(dao, settings, votingToken, taikoL1, taikoBridge);
    }

    function test_InitializeSetsTheRightValues() public {
        // Initial settings
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 7 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );
        (uint32 minVetoRatio, uint64 minDuration, uint64 l2InactivityPeriod, uint64 l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 10), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 10), "Incorrect minVetoRatio");
        assertEq(minDuration, 7 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 10 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 2 days, "Incorrect l2AggregationGracePeriod");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 10 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different minVetoRatio
        settings.minVetoRatio = uint32(RATIO_BASE / 5);
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );
        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 7 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 10 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 2 days, "Incorrect l2AggregationGracePeriod");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 10 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different minDuration
        settings.minDuration = 25 days;
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 10 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 2 days, "Incorrect l2AggregationGracePeriod");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 10 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different l2InactivityPeriod
        settings.l2InactivityPeriod = 30 minutes;
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 2 days, "Incorrect l2AggregationGracePeriod");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 10 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different l2AggregationGracePeriod
        settings.l2AggregationGracePeriod = 5 days;
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 5 days, "Incorrect l2AggregationGracePeriod");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 10 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different token with 23 eth supply
        votingToken = ERC20VotesMock(
            createProxyAndCall(address(VOTING_TOKEN_BASE), abi.encodeCall(ERC20VotesMock.initialize, ()))
        );
        votingToken.mint(alice, 23 ether);
        timeForward(5);

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 5 days, "Incorrect l2AggregationGracePeriod");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 23 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different taikoL1 contract
        taikoL1 = TaikoL1(address(0x1234));
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 5 days, "Incorrect l2AggregationGracePeriod");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 23 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different taikoBridge contract
        address newTaikoBridge = address(0x5678);
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, newTaikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 5 days, "Incorrect l2AggregationGracePeriod");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 23 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(newTaikoBridge), "Incorrect taikoBridge");
    }

    function test_InitializeEmitsEvent() public {
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });

        vm.expectEmit();
        emit Initialized(uint8(1));

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );
    }

    // Getters
    function test_SupportsIProposalInterface() public view {
        bool supported = optimisticPlugin.supportsInterface(type(IProposal).interfaceId);
        assertEq(supported, true, "Should support IProposal");
    }

    function test_SupportsIERC165UpgradeableInterface() public view {
        bool supported = optimisticPlugin.supportsInterface(type(IERC165Upgradeable).interfaceId);
        assertEq(supported, true, "Should support IERC165Upgradeable");
    }

    function testFuzz_SupportsInterfaceReturnsFalseOtherwise(bytes4 _randomInterfaceId) public view {
        bool supported = optimisticPlugin.supportsInterface(bytes4(0x000000));
        assertEq(supported, false, "Should not support any other interface");

        supported = optimisticPlugin.supportsInterface(bytes4(0xffffffff));
        assertEq(supported, false, "Should not support any other interface");

        // Skip the values that can be true
        if (
            _randomInterfaceId == type(IERC165Upgradeable).interfaceId
                || _randomInterfaceId == type(IPlugin).interfaceId || _randomInterfaceId == type(IProposal).interfaceId
                || _randomInterfaceId == type(IERC1822ProxiableUpgradeable).interfaceId
                || _randomInterfaceId == type(IOptimisticTokenVoting).interfaceId
                || _randomInterfaceId == type(IMembership).interfaceId
        ) {
            return;
        }

        supported = optimisticPlugin.supportsInterface(_randomInterfaceId);
        assertEq(supported, false, "Should not support any other interface");
    }

    function test_VotingTokenReturnsTheRightAddress() public {
        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect voting token");

        address oldToken = address(optimisticPlugin.votingToken());

        // New token
        votingToken = ERC20VotesMock(
            createProxyAndCall(address(VOTING_TOKEN_BASE), abi.encodeCall(ERC20VotesMock.initialize, ()))
        );

        // Deploy a new optimisticPlugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect voting token");
        assertEq(address(votingToken) != oldToken, true, "The token address sould have changed");
    }

    function test_TotalVotingPowerReturnsTheRightValue() public {
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 10 ether, "Incorrect total voting power");
        assertEq(votingToken.getPastTotalSupply(block.timestamp - 1), 10 ether, "Incorrect past supply");

        // 2
        builder = new DaoBuilder();
        (, optimisticPlugin,,, votingToken,) = builder.withTokenHolder(alice, 5 ether).withTokenHolder(bob, 200 ether)
            .withTokenHolder(carol, 2.5 ether).build();

        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 207.5 ether, "Incorrect total voting power");
        assertEq(votingToken.getPastTotalSupply(block.timestamp - 1), 207.5 ether, "Incorrect past supply");

        // 2
        builder = new DaoBuilder();
        (, optimisticPlugin,,, votingToken,) = builder.withTokenHolder(alice, 50 ether).withTokenHolder(bob, 30 ether)
            .withTokenHolder(carol, 0.1234 ether).withTokenHolder(david, 100 ether).build();

        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 180.1234 ether, "Incorrect total voting power");
        assertEq(votingToken.getPastTotalSupply(block.timestamp - 1), 180.1234 ether, "Incorrect past supply");
    }

    function test_MinVetoRatioReturnsTheRightValue() public {
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 10), "Incorrect minVetoRatio");

        // 2
        builder = new DaoBuilder();
        (, optimisticPlugin,,, votingToken,) = builder.withMinVetoRatio(1_000).build();

        assertEq(optimisticPlugin.minVetoRatio(), 1_000, "Incorrect minVetoRatio");

        // 3
        builder = new DaoBuilder();
        (, optimisticPlugin,,, votingToken,) = builder.withMinVetoRatio(500_000).build();

        assertEq(optimisticPlugin.minVetoRatio(), 500_000, "Incorrect minVetoRatio");

        // 4
        builder = new DaoBuilder();
        (, optimisticPlugin,,, votingToken,) = builder.withMinVetoRatio(300_000).build();

        assertEq(optimisticPlugin.minVetoRatio(), 300_000, "Incorrect minVetoRatio");
    }

    function test_TokenHoldersAreMembers() public {
        assertEq(optimisticPlugin.isMember(alice), true, "Alice should not be a member");
        assertEq(optimisticPlugin.isMember(bob), false, "Bob should not be a member");
        assertEq(optimisticPlugin.isMember(randomWallet), false, "Random wallet should not be a member");

        // New token
        votingToken = ERC20VotesMock(
            createProxyAndCall(address(VOTING_TOKEN_BASE), abi.encodeCall(ERC20VotesMock.initialize, ()))
        );
        votingToken.mint(alice, 10 ether);
        votingToken.mint(bob, 5 ether);
        timeForward(1);

        // Deploy a new optimisticPlugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        assertEq(optimisticPlugin.isMember(alice), true, "Alice should be a member");
        assertEq(optimisticPlugin.isMember(bob), true, "Bob should be a member");
        assertEq(optimisticPlugin.isMember(randomWallet), false, "Random wallet should not be a member");
    }

    // Create proposal
    function test_CreateProposalRevertsWhenCalledByANonProposer() public {
        switchTo(alice);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(optimisticPlugin),
                alice,
                optimisticPlugin.PROPOSER_PERMISSION_ID()
            )
        );
        optimisticPlugin.createProposal("", actions, 0, 0);

        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.PROPOSER_PERMISSION_ID());
        optimisticPlugin.createProposal("", actions, 0, 0);

        undoSwitch();
        switchTo(bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(optimisticPlugin),
                bob,
                optimisticPlugin.PROPOSER_PERMISSION_ID()
            )
        );
        optimisticPlugin.createProposal("", actions, 0, 0);
    }

    function test_CreateProposalRevertsIfThereIsNoVotingPower() public {
        switchTo(alice);

        // Deploy ERC20 token (0 supply)
        votingToken = ERC20VotesMock(
            createProxyAndCall(address(VOTING_TOKEN_BASE), abi.encodeCall(ERC20VotesMock.initialize, ()))
        );

        // Deploy a new optimisticPlugin instance
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );
        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.PROPOSER_PERMISSION_ID());

        // Try to create
        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPlugin.NoVotingPower.selector));
        optimisticPlugin.createProposal("", actions, 0, 0);
    }

    function test_CreateProposalRevertsIfEndDateIsEarlierThanMinDuration() public {
        setTime(500); // timestamp = 500

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.DateOutOfBounds.selector, 10 days, 10 minutes)
        );
        optimisticPlugin.createProposal("", actions, 0, 10 minutes);
    }

    function test_CreateProposalStartsNow() public {
        setTime(500);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 0);

        (bool _open,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Incorrect open status");
    }

    function test_CreateProposalEndsAfterMinDuration() public {
        setTime(500);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 0);

        timeForward(10 days);
        (,, OptimisticTokenVotingPlugin.ProposalParameters memory parameters,,,) =
            optimisticPlugin.getProposal(proposalId);
        assertEq(500 + 10 days, parameters.vetoEndDate, "Incorrect vetoEndDate");
    }

    function test_CreateProposalUsesTheCurrentMinVetoRatio() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 0);

        (,, OptimisticTokenVotingPlugin.ProposalParameters memory parameters,,,) =
            optimisticPlugin.getProposal(proposalId);
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");

        // Now with a different value
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.PROPOSER_PERMISSION_ID());
        proposalId = optimisticPlugin.createProposal("", actions, 0, 0);
        (,, parameters,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(parameters.minVetoRatio, 200_000, "Incorrect minVetoRatio");
    }

    function test_CreateProposalReturnsTheProposalId() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 0);
        uint256 expectedPid = uint256(block.timestamp) << 128 | uint256(block.timestamp + 10 days) << 64;
        assertEq(proposalId, expectedPid, "Should have created proposal 0");

        proposalId = optimisticPlugin.createProposal("", actions, 0, 0);
        expectedPid = (uint256(block.timestamp) << 128 | uint256(block.timestamp + 10 days) << 64) + 1;
        assertEq(proposalId, expectedPid, "Should have created proposal 1");
    }

    function test_CreateProposalEmitsAnEvent() public {
        uint256 expectedPid = uint256(block.timestamp) << 128 | uint256(block.timestamp + 10 days) << 64;

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectEmit();
        emit ProposalCreated(
            expectedPid, alice, uint64(block.timestamp), uint64(block.timestamp + 10 days), "", actions, 0
        );
        optimisticPlugin.createProposal("", actions, 0, 0);
    }

    function test_ParseProposalIdReturnsTheRightValues() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId1 = optimisticPlugin.createProposal("", actions, 0, 0);

        timeForward(23456);
        uint256 proposalId2 = optimisticPlugin.createProposal("", actions, 0, 0);

        (uint256 counter1, uint64 startDate1, uint64 endDate1) = optimisticPlugin.parseProposalId(proposalId1);
        (uint256 counter2, uint64 startDate2, uint64 endDate2) = optimisticPlugin.parseProposalId(proposalId2);

        assertEq(counter1, 0, "Counter should be 0");
        assertEq(counter2, 1, "Counter should be 1");
        assertEq(startDate2 - startDate1, 23456, "Date diff should be +23456");
        assertEq(endDate2 - endDate1, 23456, "Date diff should be +23456");
    }

    function test_GetProposalReturnsTheRightValues() public {
        setTime(500);
        uint32 vetoPeriod = 15 days;

        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].to = address(optimisticPlugin);
        actions[0].value = 1 wei;
        actions[0].data = abi.encodeCall(OptimisticTokenVotingPlugin.totalVotingPower, (0));
        uint256 failSafeBitmap = 1;

        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, failSafeBitmap, vetoPeriod);

        (bool open0,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(open0, false, "The proposal should not be open");

        // Move on
        setTime(block.timestamp + vetoPeriod);

        (
            bool open,
            bool executed,
            OptimisticTokenVotingPlugin.ProposalParameters memory parameters,
            uint256 vetoTally,
            IDAO.Action[] memory actualActions,
            uint256 actualFailSafeBitmap
        ) = optimisticPlugin.getProposal(proposalId);

        assertEq(open, true, "The proposal should be open");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(parameters.vetoEndDate, 500 + 15 days, "Incorrect startDate");
        assertEq(parameters.snapshotTimestamp, 499, "Incorrect snapshotTimestamp");
        assertEq(
            parameters.minVetoRatio,
            optimisticPlugin.totalVotingPower(block.timestamp - 1) / 10,
            "Incorrect minVetoRatio"
        );
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 1, "Actions should have one item");
        assertEq(actualFailSafeBitmap, failSafeBitmap, "Incorrect failsafe bitmap");

        // Move on
        timeForward(15 days);

        (bool open1,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(open1, false, "The proposal should not be open anymore");
    }

    // Can Veto
    function test_CanVetoReturnsFalseWhenAProposalDoesntExist() public {
        vm.roll(10);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 0);
        vm.roll(20);

        assertEq(optimisticPlugin.canVeto(proposalId, alice), true, "Alice should be able to veto");

        // non existing
        assertEq(
            optimisticPlugin.canVeto(proposalId + 200, alice),
            false,
            "Alice should not be able to veto on non existing proposals"
        );
    }

    function testFuzz_CanVetoReturnsFalseForNonExistingProposals(uint256 _randomProposalId) public view {
        // Non existing
        assertEq(optimisticPlugin.canVeto(_randomProposalId, alice), false, "Alice should not be able to veto");
        assertEq(optimisticPlugin.canVeto(_randomProposalId, bob), false, "Bob should not be able to veto");
        assertEq(optimisticPlugin.canVeto(_randomProposalId, carol), false, "Carol should not be able to veto");
        assertEq(optimisticPlugin.canVeto(_randomProposalId, david), false, "David should not be able to veto");
        assertEq(
            optimisticPlugin.canVeto(_randomProposalId, randomWallet), false, "RandomWallet should not be able to veto"
        );
    }

    function test_CanVetoReturnsFalseWhenAVoterAlreadyVetoed() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 10 minutes);
        timeForward(1);

        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.canVeto(proposalId, alice), false, "Alice should not be able to veto");
    }

    function test_CanVetoReturnsFalseWhenAVoterAlreadyEnded() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);
        setTime(endDate + 1);

        assertEq(optimisticPlugin.canVeto(proposalId, alice), false, "Alice should not be able to veto");
    }

    function test_CanVetoReturnsFalseWhenNoVotingPower() public {
        uint64 startDate = 50;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        setTime(startDate + 1);

        // Alice owns tokens
        assertEq(optimisticPlugin.canVeto(proposalId, alice), true, "Alice should be able to veto");

        // Bob owns no tokens
        assertEq(optimisticPlugin.canVeto(proposalId, bob), false, "Bob should not be able to veto");
    }

    function test_CanVetoReturnsTrueOtherwise() public {
        uint64 startDate = 50;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);
        setTime(startDate + 1);

        assertEq(optimisticPlugin.canVeto(proposalId, alice), true, "Alice should be able to veto");
    }

    // Veto
    function test_VetoRevertsWhenAProposalDoesntExist() public {
        vm.roll(10);
        uint64 startDate = 50;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);
        vm.roll(20);

        // non existing
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector, proposalId + 200, alice
            )
        );
        optimisticPlugin.veto(proposalId + 200);
    }

    function test_VetoRevertsWhenAProposalHasNotStarted() public {
        uint64 startDate = 50;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        // Unstarted
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector, proposalId, alice)
        );
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), false, "Alice should not have vetoed");

        // Started
        setTime(startDate + 1);
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");
    }

    function test_VetoRevertsWhenAVoterAlreadyVetoed() public {
        uint64 startDate = 50;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);
        setTime(startDate + 1);

        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), false, "Alice should not have vetoed");
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector, proposalId, alice)
        );
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");
    }

    function test_VetoRevertsWhenAVoterAlreadyEnded() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);
        setTime(endDate + 1);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector, proposalId, alice)
        );
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), false, "Alice should not have vetoed");
    }

    function test_VetoRevertsWhenNoVotingPower() public {
        uint64 startDate = 50;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        setTime(startDate + 1);

        vm.stopPrank();
        vm.startPrank(bob);

        // Bob owns no tokens
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector, proposalId, bob)
        );
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, bob), false, "Bob should not have vetoed");

        vm.stopPrank();
        vm.startPrank(alice);

        // Alice owns tokens
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");
    }

    function test_VetoRegistersAVetoForTheTokenHolderAndIncreasesTheTally() public {
        uint64 startDate = 50;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);
        setTime(startDate + 1);

        (,,, uint256 tally1,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(tally1, 0, "Tally should be zero");

        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");

        (,,, uint256 tally2,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(tally2, 10 ether, "Tally should be 10 eth");
    }

    function test_VetoEmitsAnEvent() public {
        uint64 startDate = 50;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);
        setTime(startDate + 1);

        vm.expectEmit();
        emit VetoCast(proposalId, alice, 10 ether);
        optimisticPlugin.veto(proposalId);
    }

    // Has vetoed
    function test_HasVetoedReturnsTheRightValues() public {
        uint64 startDate = 50;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);
        setTime(startDate + 1);

        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), false, "Alice should not have vetoed");
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");
    }

    // Can execute
    function test_CanExecuteReturnsFalseWhenNotEnded() public {
        uint64 startDate = 50;
        // uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");

        setTime(startDate + 1);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable yet");
    }

    function test_CanExecuteReturnsFalseWhenDefeated() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");

        setTime(startDate + 1);

        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable yet");

        setTime(endDate + 1);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");
    }

    function test_CanExecuteReturnsFalseWhenAlreadyExecuted() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        setTime(endDate + 1);
        assertEq(optimisticPlugin.canExecute(proposalId), true, "The proposal should be executable");

        optimisticPlugin.execute(proposalId);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");
    }

    function test_CanExecuteReturnsTrueOtherwise() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");

        setTime(startDate + 1);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable yet");

        setTime(endDate + 1);

        assertEq(optimisticPlugin.canExecute(proposalId), true, "The proposal should be executable");
    }

    // Veto threshold reached
    function test_IsMinVetoRatioReachedReturnsTheAppropriateValues() public {
        // Deploy ERC20 token
        votingToken = ERC20VotesMock(
            createProxyAndCall(address(VOTING_TOKEN_BASE), abi.encodeCall(ERC20VotesMock.initialize, ()))
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

        blockForward(1);

        // Deploy a new optimisticPlugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32((RATIO_BASE * 25) / 100),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        vm.stopPrank();
        vm.startPrank(alice);

        // Permissions
        dao.grant(address(dao), address(optimisticPlugin), dao.EXECUTE_PERMISSION_ID());
        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.PROPOSER_PERMISSION_ID());

        uint64 startDate = 50;
        // uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        setTime(startDate + 1);

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");
        // Alice vetoes 24%
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");

        vm.stopPrank();
        vm.startPrank(bob);

        // Bob vetoes +1% => met
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), true, "The veto threshold should be met");

        vm.stopPrank();
        vm.startPrank(randomWallet);

        // Random wallet vetoes +75% => still met
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), true, "The veto threshold should still be met");
    }

    // Execute
    function test_ExecuteRevertsWhenNotEnded() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        setTime(startDate + 1);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        setTime(endDate);
        optimisticPlugin.execute(proposalId);

        (, bool executed,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, true, "The proposal should be executed");
    }

    function test_ExecuteRevertsWhenDefeated() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        setTime(startDate + 1);

        optimisticPlugin.veto(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        setTime(endDate + 1);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        (, bool executed,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, false, "The proposal should not be executed");
    }

    function test_ExecuteRevertsWhenAlreadyExecuted() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        setTime(endDate + 1);

        optimisticPlugin.execute(proposalId);

        (, bool executed1,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed1, true, "The proposal should be executed");

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        (, bool executed2,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed2, true, "The proposal should be executed");
    }

    function test_ExecuteSucceedsOtherwise() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        setTime(endDate + 1);

        optimisticPlugin.execute(proposalId);
    }

    function test_ExecuteMarksTheProposalAsExecuted() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        setTime(endDate + 1);

        optimisticPlugin.execute(proposalId);

        (, bool executed2,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed2, true, "The proposal should be executed");
    }

    function test_ExecuteEmitsAnEvent() public {
        uint64 startDate = 50;
        uint64 endDate = startDate + 10 days;
        setTime(startDate - 1);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, startDate);

        setTime(endDate + 1);

        vm.expectEmit();
        emit ProposalExecuted(proposalId);
        optimisticPlugin.execute(proposalId);
    }

    // Update settings
    function test_UpdateOptimisticGovernanceSettingsRevertsWhenNoPermission() public {
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory newSettings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 15 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(optimisticPlugin),
                alice,
                optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
            )
        );
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);

        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsRevertsWhenTheMinVetoRatioIsZero() public {
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory newSettings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: 0,
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        vm.expectRevert(abi.encodeWithSelector(RatioOutOfBounds.selector, 1, 0));
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsRevertsWhenTheMinVetoRatioIsAboveTheMaximum() public {
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory newSettings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE + 1),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        vm.expectRevert(abi.encodeWithSelector(RatioOutOfBounds.selector, RATIO_BASE, uint32(RATIO_BASE + 1)));
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsRevertsWhenTheMinDurationIsLessThanFourDays() public {
        // This test is not applicable, since the minimum boundary is intentionally left open
        vm.skip(true);

        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory newSettings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 4 days - 1,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector, 4 days, 4 days - 1)
        );
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);

        // 2
        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 hours,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector, 4 days, 10 hours)
        );
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);

        // 3
        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 0 ether,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector, 4 days, 0));
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsRevertsWhenTheMinDurationIsMoreThanOneYear() public {
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory newSettings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 365 days + 1 ether,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector, 365 days, 365 days + 1)
        );
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);

        // 2
        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 500 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector, 365 days, 500 days)
        );
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);

        // 3
        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 1000 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.MinDurationOutOfBounds.selector, 365 days, 1000 days)
        );
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsEmitsAnEventWhenSuccessful() public {
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory newSettings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 15 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });

        vm.expectEmit();
        emit OptimisticGovernanceSettingsUpdated({minVetoRatio: uint32(RATIO_BASE / 5), minDuration: 15 days});

        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_GovernanceSettingsReturnsTheRightValues() public {
        (uint32 minVetoRatio, uint64 minDuration, uint64 l2InactivityPeriod, uint64 l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();

        assertEq(minVetoRatio, uint32(RATIO_BASE / 10));
        assertEq(minDuration, 10 days);
        assertEq(l2InactivityPeriod, 10 minutes);
        assertEq(l2AggregationGracePeriod, 2 days);

        // Deploy a new optimisticPlugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory newSettings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 2),
            minDuration: 0,
            l2InactivityPeriod: 15 minutes,
            l2AggregationGracePeriod: 73 days
        });

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, newSettings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(minVetoRatio, uint32(RATIO_BASE / 2));
        assertEq(minDuration, 0);
        assertEq(l2InactivityPeriod, 15 minutes);
        assertEq(l2AggregationGracePeriod, 73 days);

        // updated settings
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 15 days,
            l2InactivityPeriod: 0,
            l2AggregationGracePeriod: 1234 minutes
        });

        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod) =
            optimisticPlugin.governanceSettings();
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5));
        assertEq(minDuration, 15 days);
        assertEq(l2InactivityPeriod, 0);
        assertEq(l2AggregationGracePeriod, 1234 minutes);
    }

    // Upgrade optimisticPlugin
    function test_UpgradeToRevertsWhenCalledFromNonUpgrader() public {
        address _newImplementation = address(new OptimisticTokenVotingPlugin());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(optimisticPlugin),
                alice,
                optimisticPlugin.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );

        optimisticPlugin.upgradeTo(_newImplementation);

        assertEq(optimisticPlugin.implementation(), address(OPTIMISTIC_BASE));
    }

    function test_UpgradeToAndCallRevertsWhenCalledFromNonUpgrader() public {
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        address _newImplementation = address(new OptimisticTokenVotingPlugin());

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 15 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(optimisticPlugin),
                alice,
                optimisticPlugin.UPGRADE_PLUGIN_PERMISSION_ID()
            )
        );

        optimisticPlugin.upgradeToAndCall(
            _newImplementation,
            abi.encodeCall(OptimisticTokenVotingPlugin.updateOptimisticGovernanceSettings, (settings))
        );

        assertEq(optimisticPlugin.implementation(), address(OPTIMISTIC_BASE));
    }

    function test_UpgradeToSucceedsWhenCalledFromUpgrader() public {
        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.UPGRADE_PLUGIN_PERMISSION_ID());

        address _newImplementation = address(new OptimisticTokenVotingPlugin());

        vm.expectEmit();
        emit Upgraded(_newImplementation);

        optimisticPlugin.upgradeTo(_newImplementation);

        assertEq(optimisticPlugin.implementation(), address(_newImplementation));
    }

    function test_UpgradeToAndCallSucceedsWhenCalledFromUpgrader() public {
        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.UPGRADE_PLUGIN_PERMISSION_ID());
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        address _newImplementation = address(new OptimisticTokenVotingPlugin());

        vm.expectEmit();
        emit Upgraded(_newImplementation);

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 15 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });
        optimisticPlugin.upgradeToAndCall(
            _newImplementation,
            abi.encodeCall(OptimisticTokenVotingPlugin.updateOptimisticGovernanceSettings, (settings))
        );

        assertEq(optimisticPlugin.implementation(), address(_newImplementation));
    }
}
