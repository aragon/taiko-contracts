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
import {GovernanceERC20Mock} from "./mocks/GovernanceERC20Mock.sol";
import {ITaikoL1} from "../src/adapted-dependencies/ITaikoL1.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IERC1822ProxiableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol";
import {createProxyAndCall} from "../src/helpers/proxy.sol";

contract OptimisticTokenVotingPluginTest is AragonTest {
    DaoBuilder builder;

    DAO dao;
    OptimisticTokenVotingPlugin optimisticPlugin;
    GovernanceERC20Mock votingToken;
    ITaikoL1 taikoL1;

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
    event OptimisticGovernanceSettingsUpdated(
        uint32 minVetoRatio, uint64 minDuration, uint64 l2AggregationGracePeriod, uint64 l2InactivityPeriod, bool skipL2
    );
    event Upgraded(address indexed implementation);

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        // alice has root permission on the DAO, is a multisig member, holds tokens and can create proposals
        // on the optimistic token voting plugin
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.build();
    }

    // Initialize
    function test_InitializeRevertsIfInitialized() public {
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });

        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        optimisticPlugin.initialize(dao, settings, votingToken, address(taikoL1), taikoBridge);
    }

    function test_InitializeSetsTheRightValues() public {
        // Initial settings
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 7 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );
        (
            uint32 minVetoRatio,
            uint64 minDuration,
            uint64 l2InactivityPeriod,
            uint64 l2AggregationGracePeriod,
            bool skipL2
        ) = optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 10), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 10), "Incorrect minVetoRatio");
        assertEq(minDuration, 7 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 10 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 2 days, "Incorrect l2AggregationGracePeriod");
        assertEq(skipL2, false, "Incorrect skipL2");

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
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );
        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 7 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 10 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 2 days, "Incorrect l2AggregationGracePeriod");
        assertEq(skipL2, false, "Incorrect skipL2");

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
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 10 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 2 days, "Incorrect l2AggregationGracePeriod");
        assertEq(skipL2, false, "Incorrect skipL2");

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
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 2 days, "Incorrect l2AggregationGracePeriod");
        assertEq(skipL2, false, "Incorrect skipL2");

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
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 5 days, "Incorrect l2AggregationGracePeriod");
        assertEq(skipL2, false, "Incorrect skipL2");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 10 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different skipL2
        settings.skipL2 = true;
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 5 days, "Incorrect l2AggregationGracePeriod");
        assertEq(skipL2, true, "Incorrect skipL2");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 10 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different token with 23 eth supply
        votingToken = new GovernanceERC20Mock(address(dao));
        votingToken.mintTo(alice, 23 ether);
        vm.warp(block.timestamp + 5);

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 5 days, "Incorrect l2AggregationGracePeriod");
        assertEq(skipL2, true, "Incorrect skipL2");

        assertEq(address(optimisticPlugin.votingToken()), address(votingToken), "Incorrect votingToken");
        assertEq(optimisticPlugin.totalVotingPower(block.timestamp - 1), 23 ether, "Incorrect token supply");
        assertEq(address(optimisticPlugin.taikoL1()), address(taikoL1), "Incorrect taikoL1");
        assertEq(address(optimisticPlugin.taikoBridge()), address(taikoBridge), "Incorrect taikoBridge");

        // Different taikoL1 contract
        taikoL1 = ITaikoL1(address(0x1234));
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 5 days, "Incorrect l2AggregationGracePeriod");
        assertEq(skipL2, true, "Incorrect skipL2");

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
                    OptimisticTokenVotingPlugin.initialize,
                    (dao, settings, votingToken, address(taikoL1), newTaikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(optimisticPlugin.minVetoRatio(), uint32(RATIO_BASE / 5), "Incorrect minVetoRatio()");
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio");
        assertEq(minDuration, 25 days, "Incorrect minDuration");
        assertEq(l2InactivityPeriod, 30 minutes, "Incorrect l2InactivityPeriod");
        assertEq(l2AggregationGracePeriod, 5 days, "Incorrect l2AggregationGracePeriod");
        assertEq(skipL2, true, "Incorrect skipL2");

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
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });

        vm.expectEmit();
        emit Initialized(uint8(1));

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
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
        votingToken = new GovernanceERC20Mock(address(dao));

        // Deploy a new optimisticPlugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
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

    function test_BridgedVotingPowerReturnsTheRightValue() public {
        // No bridged tokens
        assertEq(optimisticPlugin.bridgedVotingPower(block.timestamp - 1), 0, "Incorrect bridged voting power");
        assertEq(votingToken.getPastVotes(taikoBridge, block.timestamp - 1), 0, "Incorrect past votes");
        assertEq(votingToken.getPastTotalSupply(block.timestamp - 1), 10 ether, "Incorrect past supply");

        // 1 bridged tokens
        builder = new DaoBuilder();
        (, optimisticPlugin,,, votingToken,) =
            builder.withTokenHolder(alice, 10 ether).withTokenHolder(taikoBridge, 10 ether).build();

        assertEq(optimisticPlugin.bridgedVotingPower(block.timestamp - 1), 10 ether, "Incorrect bridged voting power");
        assertEq(votingToken.getPastVotes(taikoBridge, block.timestamp - 1), 10 ether, "Incorrect past votes");
        assertEq(votingToken.getPastTotalSupply(block.timestamp - 1), 20 ether, "Incorrect past supply");

        // 2 bridged tokens
        builder = new DaoBuilder();
        (, optimisticPlugin,,, votingToken,) = builder.withTokenHolder(alice, 10 ether).withTokenHolder(bob, 1 ether)
            .withTokenHolder(taikoBridge, 1).build();

        assertEq(optimisticPlugin.bridgedVotingPower(block.timestamp - 1), 1, "Incorrect bridged voting power");
        assertEq(votingToken.getPastVotes(taikoBridge, block.timestamp - 1), 1, "Incorrect past votes");
        assertEq(votingToken.getPastTotalSupply(block.timestamp - 1), 11 ether + 1, "Incorrect past supply");
    }

    function test_EffectiveVotingPowerReturnsTheRightValue() public {
        // No bridged tokens
        assertEq(
            optimisticPlugin.effectiveVotingPower(block.timestamp - 1, false),
            10 ether,
            "Incorrect effective voting power"
        );
        assertEq(
            optimisticPlugin.effectiveVotingPower(block.timestamp - 1, true),
            10 ether,
            "Incorrect effective voting power"
        );

        // 1 bridged tokens
        builder = new DaoBuilder();
        (, optimisticPlugin,,, votingToken,) =
            builder.withTokenHolder(alice, 10 ether).withTokenHolder(taikoBridge, 10 ether).build();

        assertEq(
            optimisticPlugin.effectiveVotingPower(block.timestamp - 1, false),
            10 ether,
            "Incorrect effective voting power"
        );
        assertEq(
            optimisticPlugin.effectiveVotingPower(block.timestamp - 1, true),
            20 ether,
            "Incorrect effective voting power"
        );

        // 2 bridged tokens
        builder = new DaoBuilder();
        (, optimisticPlugin,,, votingToken,) = builder.withTokenHolder(alice, 10 ether).withTokenHolder(bob, 1 ether)
            .withTokenHolder(taikoBridge, 1234).build();

        assertEq(
            optimisticPlugin.effectiveVotingPower(block.timestamp - 1, false),
            11 ether,
            "Incorrect effective voting power"
        );
        assertEq(
            optimisticPlugin.effectiveVotingPower(block.timestamp - 1, true),
            11 ether + 1234,
            "Incorrect effective voting power"
        );
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
        votingToken = new GovernanceERC20Mock(address(dao));
        votingToken.mintTo(alice, 10 ether);
        votingToken.mintTo(bob, 5 ether);
        vm.warp(block.timestamp + 1);

        // Deploy a new optimisticPlugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );

        assertEq(optimisticPlugin.isMember(alice), true, "Alice should be a member");
        assertEq(optimisticPlugin.isMember(bob), true, "Bob should be a member");
        assertEq(optimisticPlugin.isMember(randomWallet), false, "Random wallet should not be a member");
    }

    function test_IsL2AvailableReturnsTheRightValues() public {
        assertEq(optimisticPlugin.isL2Available(), true, "isL2Available should be true");

        // skipL2 setting
        (, optimisticPlugin,,, votingToken,) = builder.withSkipL2().build();
        assertEq(optimisticPlugin.isL2Available(), false, "isL2Available should be false");
        builder.withoutSkipL2();

        // paused
        (, optimisticPlugin,,, votingToken,) = builder.withPausedTaikoL1().build();
        assertEq(optimisticPlugin.isL2Available(), false, "isL2Available should be false");

        // out of sync
        (, optimisticPlugin,,, votingToken,) = builder.withOutOfSyncTaikoL1().build();
        assertEq(optimisticPlugin.isL2Available(), false, "isL2Available should be false");

        // out of sync: diff below lowerl2InactivityPeriod
        vm.warp(5 minutes);
        assertEq(optimisticPlugin.isL2Available(), true, "isL2Available should be true");

        // out of sync: still within the period
        vm.warp(50 days);
        (, optimisticPlugin,,, votingToken,) = builder.withL2InactivityPeriod(50 days).build();
        assertEq(optimisticPlugin.isL2Available(), true, "isL2Available should be true");

        // out of sync: over
        vm.warp(50 days + 1);
        (, optimisticPlugin,,, votingToken,) = builder.withL2InactivityPeriod(50 days).build();
        assertEq(optimisticPlugin.isL2Available(), false, "isL2Available should be false");
    }

    // Create proposal
    function test_CreateProposalRevertsWhenCalledByANonProposer() public {
        vm.startPrank(bob);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(optimisticPlugin),
                bob,
                optimisticPlugin.PROPOSER_PERMISSION_ID()
            )
        );
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        vm.startPrank(alice);
        dao.grant(address(optimisticPlugin), bob, optimisticPlugin.PROPOSER_PERMISSION_ID());
        vm.startPrank(bob);
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        vm.startPrank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(optimisticPlugin),
                carol,
                optimisticPlugin.PROPOSER_PERMISSION_ID()
            )
        );
        optimisticPlugin.createProposal("", actions, 0, 4 days);
    }

    function test_CreateProposalRevertsIfThereIsNoVotingPowerOnlyL1Tokens() public {
        // 1
        // Paused L2
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withPausedTaikoL1().withTokenHolder(alice, 0).withProposerOnOptimistic(alice).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPlugin.NoVotingPower.selector));
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        votingToken.mint();
        vm.warp(block.timestamp + 1);

        // Now ok
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        // 2
        // Out of sync L2
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withOutOfSyncTaikoL1().withTokenHolder(alice, 0).withProposerOnOptimistic(alice).build();

        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPlugin.NoVotingPower.selector));
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        votingToken.mint();
        vm.warp(block.timestamp + 1);

        // Now ok
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        // 3
        // Taiko Bridge now has voting power (should be ignored)
        // Paused L2
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withPausedTaikoL1().withTokenHolder(
            taikoBridge, 10000 ether
        ).withProposerOnOptimistic(alice).build();

        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPlugin.NoVotingPower.selector));
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        votingToken.mint();
        vm.warp(block.timestamp + 1);

        // Now ok
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        // 4
        // Out of sync L2
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withOutOfSyncTaikoL1().withTokenHolder(
            taikoBridge, 10000 ether
        ).withProposerOnOptimistic(alice).build();

        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPlugin.NoVotingPower.selector));
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        votingToken.mint();
        vm.warp(block.timestamp + 1);

        // Now ok
        optimisticPlugin.createProposal("", actions, 0, 4 days);
    }

    function test_CreateProposalRevertsIfThereIsNoVotingPowerWithL1L2Tokens() public {
        // 1
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withOkTaikoL1().withTokenHolder(alice, 0).withProposerOnOptimistic(alice).build();

        // Try to create
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPlugin.NoVotingPower.selector));
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        votingToken.mint();
        vm.warp(block.timestamp + 1);

        // Now ok
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        // 2
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withOkTaikoL1().withTokenHolder(taikoBridge, 0).withProposerOnOptimistic(alice).build();

        // Try to create
        actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPlugin.NoVotingPower.selector));
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        votingToken.mintAndDelegate(taikoBridge, 10 ether);
        vm.warp(block.timestamp + 1);

        // Now ok
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        // 2
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withOkTaikoL1().withTokenHolder(taikoBridge, 0).withProposerOnOptimistic(alice).build();

        // Try to create
        actions = new IDAO.Action[](0);
        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPlugin.NoVotingPower.selector));
        optimisticPlugin.createProposal("", actions, 0, 4 days);

        votingToken.mintAndDelegate(taikoBridge, 10 ether);
        vm.warp(block.timestamp + 1);

        // Now ok
        optimisticPlugin.createProposal("", actions, 0, 4 days);
    }

    function test_CreateProposalRevertsIfDurationIsLowerThanMin() public {
        vm.startPrank(alice);
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withMinDuration(0).withProposerOnOptimistic(alice).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);

        // ok
        optimisticPlugin.createProposal("", actions, 0, 0);

        // 2 ko
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withMinDuration(10 minutes).withProposerOnOptimistic(alice).build();

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.DurationOutOfBounds.selector, 10 minutes, 9 minutes)
        );
        optimisticPlugin.createProposal("", actions, 0, 9 minutes);

        // 3 ok
        optimisticPlugin.createProposal("", actions, 0, 10 minutes);

        // 4 ko
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withMinDuration(10 hours).withProposerOnOptimistic(alice).build();

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.DurationOutOfBounds.selector, 10 hours, 9 hours)
        );
        optimisticPlugin.createProposal("", actions, 0, 9 hours);

        // 5 ok
        optimisticPlugin.createProposal("", actions, 0, 10 hours);
    }

    function test_CreateProposalStartsNow() public {
        vm.warp(2 days);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 4 days);

        (bool _open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Incorrect open status");
    }

    function test_CreateProposalStartsDespiteRevertingTaikoL1() public {
        (dao, optimisticPlugin,,,,) = builder.withIncompatibleTaikoL1().build();

        vm.warp(2 days);

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 4 days);

        (bool _open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Incorrect open status");
    }

    function test_CreateProposalEndsAfterMinDurationOnlyL1Tokens() public {
        vm.warp(50 days - 1);

        // L2 Paused
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withPausedTaikoL1().build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 10 days);

        (bool _open,, OptimisticTokenVotingPlugin.ProposalParameters memory parameters,,,,) =
            optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Should be open");
        assertEq(50 days + 10 days, parameters.vetoEndDate, "Incorrect vetoEndDate");

        // before end
        vm.warp(50 days + 10 days - 1);
        (_open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Should be open");

        // end
        vm.warp(50 days + 10 days);
        (_open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, false, "Should not be open");

        // L2 out of sync
        vm.warp(50 days - 1);

        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withOutOfSyncTaikoL1().build();

        actions = new IDAO.Action[](0);
        proposalId = optimisticPlugin.createProposal("", actions, 0, 10 days);

        (_open,, parameters,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Should be open");
        assertEq(50 days + 10 days, parameters.vetoEndDate, "Incorrect vetoEndDate");

        // before end
        vm.warp(50 days + 10 days - 1);
        (_open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Should be open");

        // end
        vm.warp(50 days + 10 days);
        (_open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, false, "Should not be open");
    }

    function test_CreateProposalEndsAfterMinDurationWithL1L2Tokens() public {
        // 1
        vm.warp(50 days - 1);
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 10 days);

        (bool _open,, OptimisticTokenVotingPlugin.ProposalParameters memory parameters,,,,) =
            optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Should be open");
        assertEq(50 days + 10 days, parameters.vetoEndDate, "Incorrect vetoEndDate");

        // before end
        vm.warp(block.timestamp + 10 days - 1);
        (_open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Should be open");

        // end
        vm.warp(block.timestamp + 1);
        (_open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, false, "Should not be open");

        // 2
        // With tokens on the Taiko Bridge
        vm.warp(50 days - 1);
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withTokenHolder(alice, 10 ether).withTokenHolder(taikoBridge, 10 ether).build();

        proposalId = optimisticPlugin.createProposal("", actions, 0, 10 days);

        (_open,, parameters,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Should be open");
        assertEq(50 days + 10 days, parameters.vetoEndDate, "Incorrect vetoEndDate");

        // before end
        vm.warp(50 days + 10 days - 1);
        (_open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, true, "Should be open");

        // end
        vm.warp(block.timestamp + 1);
        (_open,,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(_open, false, "Should not be open");
    }

    function test_CreateProposalUsesTheCurrentMinVetoRatio() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 4 days);

        (,, OptimisticTokenVotingPlugin.ProposalParameters memory parameters,,,,) =
            optimisticPlugin.getProposal(proposalId);
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");

        // Now with a different value
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });
        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );

        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.PROPOSER_PERMISSION_ID());
        proposalId = optimisticPlugin.createProposal("", actions, 0, 10 days);
        (,, parameters,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(parameters.minVetoRatio, 200_000, "Incorrect minVetoRatio");
    }

    function test_CreateProposalReturnsTheProposalId() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);

        vm.warp(2 days);
        uint256 proposalId = optimisticPlugin.createProposal("", actions, 0, 10 days);
        uint256 expectedPid = uint256(block.timestamp) << 128 | uint256(block.timestamp + 10 days) << 64;
        assertEq(proposalId, expectedPid, "Should have created proposal 0");

        vm.warp(5 days);
        proposalId = optimisticPlugin.createProposal("", actions, 0, 5 days);
        expectedPid = (uint256(block.timestamp) << 128 | uint256(block.timestamp + 5 days) << 64) + 1;
        assertEq(proposalId, expectedPid, "Should have created proposal 1");

        vm.warp(500 days);
        proposalId = optimisticPlugin.createProposal("", actions, 0, 5 days);
        expectedPid = (uint256(block.timestamp) << 128 | uint256(block.timestamp + 5 days) << 64) + 2;
        assertEq(proposalId, expectedPid, "Should have created proposal 2");
    }

    function test_CreateProposalIncrementsTheProposalCounter() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        assertEq(optimisticPlugin.proposalCount(), 0);
        optimisticPlugin.createProposal("", actions, 0, 10 days);
        assertEq(optimisticPlugin.proposalCount(), 1);
        optimisticPlugin.createProposal("ipfs://", actions, 0, 10 days);
        assertEq(optimisticPlugin.proposalCount(), 2);
        optimisticPlugin.createProposal("", actions, 255, 15 days);
        assertEq(optimisticPlugin.proposalCount(), 3);
        optimisticPlugin.createProposal("", actions, 127, 20 days);
        assertEq(optimisticPlugin.proposalCount(), 4);
        optimisticPlugin.createProposal("ipfs://meta", actions, 0, 10 days);
        assertEq(optimisticPlugin.proposalCount(), 5);
        optimisticPlugin.createProposal("", actions, 0, 100 days);
        assertEq(optimisticPlugin.proposalCount(), 6);
    }

    function test_CreateProposalIndexesThePid() public {
        uint256 expectedPid = uint256(block.timestamp) << 128 | uint256(block.timestamp + 10 days) << 64;

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        // 1
        assertEq(optimisticPlugin.proposalIds(0), 0);
        optimisticPlugin.createProposal("", actions, 0, 10 days);
        assertEq(optimisticPlugin.proposalIds(0), expectedPid);

        // 2
        expectedPid = uint256(block.timestamp) << 128 | uint256(block.timestamp + 100 days) << 64 | 1;
        assertEq(optimisticPlugin.proposalIds(1), 0);
        optimisticPlugin.createProposal("ipfs://meta", actions, 0, 100 days);
        assertEq(optimisticPlugin.proposalIds(1), expectedPid);

        // 3
        expectedPid = uint256(block.timestamp) << 128 | uint256(block.timestamp + 50 days) << 64 | 2;
        assertEq(optimisticPlugin.proposalIds(2), 0);
        optimisticPlugin.createProposal("", actions, 0, 50 days);
        assertEq(optimisticPlugin.proposalIds(2), expectedPid);
    }

    function test_CreateProposalEmitsAnEvent() public {
        uint256 expectedPid = uint256(block.timestamp) << 128 | uint256(block.timestamp + 10 days) << 64;

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        vm.expectEmit();
        emit ProposalCreated(
            expectedPid, alice, uint64(block.timestamp), uint64(block.timestamp + 10 days), "", actions, 0
        );
        optimisticPlugin.createProposal("", actions, 0, 10 days);
    }

    function test_ParseProposalIdReturnsTheRightValues() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId1 = optimisticPlugin.createProposal("", actions, 0, 4 days);

        vm.warp(block.timestamp + 23456);
        uint256 proposalId2 = optimisticPlugin.createProposal("", actions, 0, 4 days);

        (uint256 counter1, uint64 startDate1, uint64 endDate1) = optimisticPlugin.parseProposalId(proposalId1);
        (uint256 counter2, uint64 startDate2, uint64 endDate2) = optimisticPlugin.parseProposalId(proposalId2);

        assertEq(counter1, 0, "Counter should be 0");
        assertEq(counter2, 1, "Counter should be 1");
        assertEq(startDate2 - startDate1, 23456, "Date diff should be +23456");
        assertEq(endDate2 - endDate1, 23456, "Date diff should be +23456");
    }

    function test_GetProposalReturnsTheRightValuesL1OnlyAndL1L2() public {
        // 1
        vm.warp(2 days);
        uint32 vetoPeriod = 15 days;

        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0].to = address(optimisticPlugin);
        actions[0].value = 1 wei;
        actions[0].data = abi.encodeCall(OptimisticTokenVotingPlugin.totalVotingPower, (0));
        uint256 failSafeBitmap = 1;

        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, failSafeBitmap, vetoPeriod);

        (
            bool open,
            bool executed,
            OptimisticTokenVotingPlugin.ProposalParameters memory parameters,
            uint256 vetoTally,
            bytes memory metadataUri,
            IDAO.Action[] memory actualActions,
            uint256 actualFailSafeBitmap
        ) = optimisticPlugin.getProposal(proposalId);

        assertEq(open, true, "The proposal should be open");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(metadataUri, "ipfs://", "Incorrect metadataUri");
        assertEq(parameters.vetoEndDate, 2 days + 15 days, "Incorrect vetoEndDate");
        assertEq(parameters.snapshotTimestamp, 2 days - 1, "Incorrect snapshotTimestamp");
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");
        assertEq(parameters.unavailableL2, true, "L2 should be disabled"); // no bridge balance
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 1, "Actions should have one item");
        assertEq(actualFailSafeBitmap, failSafeBitmap, "Incorrect failsafe bitmap");

        // Move on
        vm.warp(block.timestamp + vetoPeriod);

        (open, executed, parameters, vetoTally, metadataUri, actualActions, actualFailSafeBitmap) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "The proposal should not be open anymore");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(metadataUri, "ipfs://", "Incorrect metadataUri");
        assertEq(parameters.vetoEndDate, 2 days + 15 days, "Incorrect vetoEndDate");
        assertEq(parameters.snapshotTimestamp, 2 days - 1, "Incorrect snapshotTimestamp");
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");
        assertEq(parameters.unavailableL2, true, "L2 should be disabled"); // no bridge balance
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 1, "Actions should have one item");
        assertEq(actualActions[0].to, actions[0].to, "Incorrect to");
        assertEq(actualActions[0].value, actions[0].value, "Incorrect value");
        assertEq(actualActions[0].data, actions[0].data, "Incorrect data");
        assertEq(actualFailSafeBitmap, failSafeBitmap, "Incorrect failsafe bitmap");

        // 2 - With L2 tokens
        vm.warp(3 days - 1);
        (dao, optimisticPlugin,,, votingToken, taikoL1) =
            builder.withTokenHolder(alice, 10 ether).withTokenHolder(taikoBridge, 10 ether).build();

        vetoPeriod = 30 days;

        actions[0].to = bob;
        actions[0].value = 5.5 ether;
        actions[0].data = abi.encodeCall(OptimisticTokenVotingPlugin.canExecute, (0));
        failSafeBitmap = 255;

        proposalId = optimisticPlugin.createProposal("ipfs://some-uri", actions, failSafeBitmap, vetoPeriod);

        (open, executed, parameters, vetoTally, metadataUri, actualActions, actualFailSafeBitmap) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, true, "The proposal should be open");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(metadataUri, "ipfs://some-uri", "Incorrect metadataUri");
        assertEq(parameters.vetoEndDate, 3 days + 30 days, "Incorrect vetoEndDate");
        assertEq(parameters.snapshotTimestamp, 3 days - 1, "Incorrect snapshotTimestamp");
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");
        assertEq(parameters.unavailableL2, false, "Incorrect unavailableL2");
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 1, "Actions should have one item");
        assertEq(actualFailSafeBitmap, failSafeBitmap, "Incorrect failsafe bitmap");

        // Move on
        vm.warp(block.timestamp + vetoPeriod);

        (open, executed, parameters, vetoTally, metadataUri, actualActions, actualFailSafeBitmap) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "The proposal should not be open anymore");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(metadataUri, "ipfs://some-uri", "Incorrect metadataUri");
        assertEq(parameters.vetoEndDate, 3 days + 30 days, "Incorrect vetoEndDate");
        assertEq(parameters.snapshotTimestamp, 3 days - 1, "Incorrect snapshotTimestamp");
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");
        assertEq(parameters.unavailableL2, false, "Incorrect unavailableL2");
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 1, "Actions should have one item");
        assertEq(actualActions[0].to, actions[0].to, "Incorrect to");
        assertEq(actualActions[0].value, actions[0].value, "Incorrect value");
        assertEq(actualActions[0].data, actions[0].data, "Incorrect data");
        assertEq(actualFailSafeBitmap, failSafeBitmap, "Incorrect failsafe bitmap");

        // 3 with L2 paused

        vm.warp(3 days - 1);
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withPausedTaikoL1().build();
        vetoPeriod = 15 days;

        actions[0].to = carol;
        actions[0].value = 1.5 ether;
        actions[0].data = abi.encodeCall(OptimisticTokenVotingPlugin.canExecute, (0));
        failSafeBitmap = 55;

        proposalId = optimisticPlugin.createProposal("ipfs://my-uri", actions, failSafeBitmap, vetoPeriod);

        (open, executed, parameters, vetoTally, metadataUri, actualActions, actualFailSafeBitmap) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, true, "The proposal should be open");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(metadataUri, "ipfs://my-uri", "Incorrect metadataUri");
        assertEq(parameters.vetoEndDate, 3 days + 15 days, "Incorrect vetoEndDate");
        assertEq(parameters.snapshotTimestamp, 3 days - 1, "Incorrect snapshotTimestamp");
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");
        assertEq(parameters.unavailableL2, true, "Incorrect unavailableL2");
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 1, "Actions should have one item");
        assertEq(actualFailSafeBitmap, failSafeBitmap, "Incorrect failsafe bitmap");

        // Move on
        vm.warp(block.timestamp + vetoPeriod);

        (open, executed, parameters, vetoTally, metadataUri, actualActions, actualFailSafeBitmap) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "The proposal should not be open anymore");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(metadataUri, "ipfs://my-uri", "Incorrect metadataUri");
        assertEq(parameters.vetoEndDate, 3 days + 15 days, "Incorrect vetoEndDate");
        assertEq(parameters.snapshotTimestamp, 3 days - 1, "Incorrect snapshotTimestamp");
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");
        assertEq(parameters.unavailableL2, true, "Incorrect unavailableL2");
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 1, "Actions should have one item");
        assertEq(actualActions[0].to, actions[0].to, "Incorrect to");
        assertEq(actualActions[0].value, actions[0].value, "Incorrect value");
        assertEq(actualActions[0].data, actions[0].data, "Incorrect data");
        assertEq(actualFailSafeBitmap, failSafeBitmap, "Incorrect failsafe bitmap");

        // 4 with L2 out of sync

        vm.warp(3 days - 1);
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withOutOfSyncTaikoL1().build();

        proposalId = optimisticPlugin.createProposal("ipfs://my-uri", actions, failSafeBitmap, vetoPeriod);

        (open, executed, parameters, vetoTally, metadataUri, actualActions, actualFailSafeBitmap) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, true, "The proposal should be open");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(metadataUri, "ipfs://my-uri", "Incorrect metadataUri");
        assertEq(parameters.vetoEndDate, 3 days + 15 days, "Incorrect vetoEndDate");
        assertEq(parameters.snapshotTimestamp, 3 days - 1, "Incorrect snapshotTimestamp");
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");
        assertEq(parameters.unavailableL2, true, "Incorrect unavailableL2");
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 1, "Actions should have one item");
        assertEq(actualFailSafeBitmap, failSafeBitmap, "Incorrect failsafe bitmap");

        // Move on
        vm.warp(block.timestamp + vetoPeriod);

        (open, executed, parameters, vetoTally, metadataUri, actualActions, actualFailSafeBitmap) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "The proposal should not be open anymore");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(metadataUri, "ipfs://my-uri", "Incorrect metadataUri");
        assertEq(parameters.vetoEndDate, 3 days + 15 days, "Incorrect vetoEndDate");
        assertEq(parameters.snapshotTimestamp, 3 days - 1, "Incorrect snapshotTimestamp");
        assertEq(parameters.minVetoRatio, 100_000, "Incorrect minVetoRatio");
        assertEq(parameters.unavailableL2, true, "Incorrect unavailableL2");
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 1, "Actions should have one item");
        assertEq(actualActions[0].to, actions[0].to, "Incorrect to");
        assertEq(actualActions[0].value, actions[0].value, "Incorrect value");
        assertEq(actualActions[0].data, actions[0].data, "Incorrect data");
        assertEq(actualFailSafeBitmap, failSafeBitmap, "Incorrect failsafe bitmap");
    }

    function testFuzz_GetProposalReturnsEmptyValuesForNonExistingOnes(uint256 randomProposalId) public view {
        (
            bool open,
            bool executed,
            OptimisticTokenVotingPlugin.ProposalParameters memory parameters,
            uint256 vetoTally,
            bytes memory metadataUri,
            IDAO.Action[] memory actualActions,
            uint256 actualFailSafeBitmap
        ) = optimisticPlugin.getProposal(randomProposalId);

        assertEq(open, false, "The proposal should not be open");
        assertEq(executed, false, "The proposal should not be executed");
        assertEq(metadataUri, "", "Incorrect metadataUri");
        assertEq(parameters.vetoEndDate, 0, "Incorrect startDate");
        assertEq(parameters.snapshotTimestamp, 0, "Incorrect snapshotTimestamp");
        assertEq(parameters.minVetoRatio, 0, "Incorrect minVetoRatio");
        assertEq(vetoTally, 0, "The tally should be zero");
        assertEq(actualActions.length, 0, "Actions should have no items");
        assertEq(actualFailSafeBitmap, 0, "Incorrect failsafe bitmap");
    }

    // Can Veto
    function testFuzz_CanVetoReturnsFalseWhenNotCreated(uint256 _randomProposalId) public {
        // Existing
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        assertEq(optimisticPlugin.canVeto(proposalId, alice), true, "Alice should be able to veto");
        assertEq(optimisticPlugin.canVeto(_randomProposalId, bob), false, "Bob should not be able to veto");
        assertEq(optimisticPlugin.canVeto(_randomProposalId, carol), false, "Carol should not be able to veto");
        assertEq(optimisticPlugin.canVeto(_randomProposalId, david), false, "David should not be able to veto");
        assertEq(
            optimisticPlugin.canVeto(_randomProposalId, randomWallet), false, "RandomWallet should not be able to veto"
        );

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
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 10 days);
        assertEq(optimisticPlugin.canVeto(proposalId, alice), true, "Alice should be able to veto");

        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.canVeto(proposalId, alice), false, "Alice should not be able to veto");
    }

    function test_CanVetoReturnsFalseWhenAVoterAlreadyEnded() public {
        uint64 votingPeriod = 10 days;

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, votingPeriod);
        assertEq(optimisticPlugin.canVeto(proposalId, alice), true, "Alice should be able to veto");

        vm.warp(block.timestamp + votingPeriod);
        assertEq(optimisticPlugin.canVeto(proposalId, alice), false, "Alice should not be able to veto");
    }

    function test_CanVetoReturnsFalseWhenNoVotingPower() public {
        uint64 votingPeriod = 10 days;

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, votingPeriod);

        // Alice owns tokens
        assertEq(optimisticPlugin.canVeto(proposalId, alice), true, "Alice should be able to veto");

        // Bob owns no tokens
        assertEq(optimisticPlugin.canVeto(proposalId, bob), false, "Bob should not be able to veto");
    }

    function test_CanVetoReturnsFalseForTheBridge() public {
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withOkTaikoL1().withTokenHolder(alice, 10 ether)
            .withTokenHolder(bob, 10 ether).withTokenHolder(taikoBridge, 10 ether).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 10 days);

        // Alice has voting power and can veto
        assertEq(optimisticPlugin.canVeto(proposalId, alice), true, "Alice should be able to veto");

        // Bob has voting power and can veto
        assertEq(optimisticPlugin.canVeto(proposalId, bob), true, "Bob should be able to veto");

        // The bridge has voting power but cannot veto
        assertEq(optimisticPlugin.canVeto(proposalId, taikoBridge), false, "The Bridge should not be able to veto");
    }

    function test_CanVetoReturnsTrueOtherwise() public {
        uint64 votingPeriod = 10 days;

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, votingPeriod);

        assertEq(optimisticPlugin.canVeto(proposalId, alice), true, "Alice should be able to veto");
    }

    // Veto
    function test_FuzzVetoRevertsWhenNotCreated(uint256 randomProposalId) public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 realProposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        // ok
        optimisticPlugin.veto(realProposalId);

        // non existing
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector, randomProposalId, alice
            )
        );
        optimisticPlugin.veto(randomProposalId);
    }

    function test_VetoRevertsWhenAVoterAlreadyVetoed() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

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
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        vm.warp(block.timestamp + 4 days);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector, proposalId, alice)
        );
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), false, "Alice should not have vetoed");
    }

    function test_VetoRevertsWhenNoVotingPower() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        // Bob owns no tokens
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector, proposalId, bob)
        );
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, bob), false, "Bob should not have vetoed");

        vm.startPrank(alice);

        // Alice owns tokens
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");
    }

    function test_VetoRevertsForTheBridge() public {
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withOkTaikoL1().withTokenHolder(alice, 10 ether)
            .withTokenHolder(bob, 10 ether).withTokenHolder(taikoBridge, 10 ether).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        // Alice has voting power
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");

        // Bob has voting power
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, bob), true, "Bob should have vetoed");

        // The Bridge has voting power but cannot veto
        vm.startPrank(taikoBridge);
        vm.expectRevert(
            abi.encodeWithSelector(
                OptimisticTokenVotingPlugin.ProposalVetoingForbidden.selector, proposalId, taikoBridge
            )
        );
        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, taikoBridge), false, "Th e Bridge should not have vetoed");
    }

    function test_VetoRegistersAVetoForTheTokenHolderAndIncreasesTheTally() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        (,,, uint256 tally1,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(tally1, 0, "Tally should be zero");

        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");

        (,,, uint256 tally2,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(tally2, 10 ether, "Tally should be 10 eth");
    }

    function test_VetoEmitsAnEvent() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        vm.expectEmit();
        emit VetoCast(proposalId, alice, 10 ether);
        optimisticPlugin.veto(proposalId);

        // 2
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withTokenHolder(alice, 5 ether).withTokenHolder(
            bob, 10 ether
        ).withTokenHolder(carol, 15 ether).build();

        proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        vm.expectEmit();
        emit VetoCast(proposalId, alice, 5 ether);
        optimisticPlugin.veto(proposalId);

        vm.startPrank(bob);
        vm.expectEmit();
        emit VetoCast(proposalId, bob, 10 ether);
        optimisticPlugin.veto(proposalId);

        vm.startPrank(carol);
        vm.expectEmit();
        emit VetoCast(proposalId, carol, 15 ether);
        optimisticPlugin.veto(proposalId);
    }

    // Has vetoed
    function test_HasVetoedReturnsTheRightValues() public {
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withTokenHolder(alice, 5 ether).withTokenHolder(
            bob, 10 ether
        ).withTokenHolder(carol, 15 ether).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), false, "Alice should not have vetoed");
        assertEq(optimisticPlugin.hasVetoed(proposalId, bob), false, "Bob should not have vetoed");
        assertEq(optimisticPlugin.hasVetoed(proposalId, carol), false, "Carol should not have vetoed");

        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");
        assertEq(optimisticPlugin.hasVetoed(proposalId, bob), false, "Bob should not have vetoed");
        assertEq(optimisticPlugin.hasVetoed(proposalId, carol), false, "Carol should not have vetoed");

        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");
        assertEq(optimisticPlugin.hasVetoed(proposalId, bob), true, "Bob should have vetoed");
        assertEq(optimisticPlugin.hasVetoed(proposalId, carol), false, "Carol should not have vetoed");

        vm.startPrank(carol);
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.hasVetoed(proposalId, alice), true, "Alice should have vetoed");
        assertEq(optimisticPlugin.hasVetoed(proposalId, bob), true, "Bob should have vetoed");
        assertEq(optimisticPlugin.hasVetoed(proposalId, carol), true, "Carol should have vetoed");
    }

    // Can execute
    function testFuzz_CanExecuteReturnsFalseWhenNotCreated(uint256 randomProposalId) public view {
        assertEq(optimisticPlugin.canExecute(randomProposalId), false, "The proposal shouldn't be executable");
    }

    function test_CanExecuteReturnsFalseWhenNotEnded() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable yet");
    }

    function test_CanExecuteReturnsFalseWhenDefeatedOnlyL1Tokens() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");

        optimisticPlugin.veto(proposalId);
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");

        vm.warp(block.timestamp + 4 days);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");
    }

    function test_CanExecuteReturnsFalseWhenDefeatedWithL1L2Tokens() public {
        vm.skip(true); // L2 aggregation still not available

        // 70% min veto ratio
        // 2 vetoes required when L1 only
        // 3 vetoes required when L1+L2

        (, optimisticPlugin,,, votingToken,) = builder.withTokenHolder(alice, 10 ether).withTokenHolder(bob, 10 ether)
            .withTokenHolder(taikoBridge, 10 ether).withMinVetoRatio(700_000).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        optimisticPlugin.veto(proposalId); // 33%
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId); // 66% (below 70%)
        // bridge supply counts but doesn't veto

        vm.warp(block.timestamp + 4 days); // end
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal should not be executable");
        vm.warp(block.timestamp + builder.l2AggregationGracePeriod()); // grace period over
        assertEq(optimisticPlugin.canExecute(proposalId), true, "The proposal should be executable");

        // L2 paused, less token supply
        // Alice and Bob are now 100%

        (, optimisticPlugin,,, votingToken,) = builder.withPausedTaikoL1().build();

        proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        optimisticPlugin.veto(proposalId); // 50%
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId); // 100% (above 70%)

        vm.warp(block.timestamp + 4 days); // end
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal should not be executable");
        vm.warp(block.timestamp + builder.l2AggregationGracePeriod()); // grace period over
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal should not be executable");

        // L2 out of sync, less token supply
        // Alice and Bob are now 100%

        (, optimisticPlugin,,, votingToken,) = builder.withOutOfSyncTaikoL1().build();

        proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        optimisticPlugin.veto(proposalId); // 50%
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId); // 100% (above 70%)

        vm.warp(block.timestamp + 4 days); // end
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal should not be executable");
        vm.warp(block.timestamp + builder.l2AggregationGracePeriod()); // grace period over
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal should not be executable");
    }

    function test_CanExecuteReturnsFalseWhenAlreadyExecuted() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        vm.warp(block.timestamp + 4 days);
        assertEq(optimisticPlugin.canExecute(proposalId), true, "The proposal should be executable");

        optimisticPlugin.execute(proposalId);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable");
    }

    function test_CanExecuteReturnsFalseWhenEndedButL2GracePeriodUnmet() public {
        // An ended proposal with L2 enabled has an additional grace period

        (, optimisticPlugin,,,,) =
            builder.withTokenHolder(alice, 10 ether).withTokenHolder(taikoBridge, 10 ether).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        (bool open, bool executed, OptimisticTokenVotingPlugin.ProposalParameters memory parameters,,,,) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, true, "Open should be true");
        assertEq(executed, false, "Executed should be false");
        assertEq(parameters.unavailableL2, false, "unavailableL2 should be false");

        // Ended
        vm.warp(block.timestamp + 4 days);
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal should not be executable yet");

        (open, executed, parameters,,,,) = optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "Open should be false");
        assertEq(executed, false, "Executed should be false");
        assertEq(parameters.unavailableL2, false, "unavailableL2 should be false");

        // Grace period almost over
        vm.warp(block.timestamp + builder.l2AggregationGracePeriod() - 1);
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal should not be executable");

        // Grace period over
        vm.warp(block.timestamp + 1);
        assertEq(optimisticPlugin.canExecute(proposalId), true, "The proposal should be executable");

        (open, executed, parameters,,,,) = optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "Open should be false");
        assertEq(executed, false, "Executed should be false");
        assertEq(parameters.unavailableL2, false, "unavailableL2 should be false");
    }

    function test_CanExecuteReturnsFalseWhenSkipL2AndEnded() public {
        // An ended proposal with L2 skipped

        (, optimisticPlugin,,,,) =
            builder.withTokenHolder(alice, 10 ether).withTokenHolder(taikoBridge, 10 ether).withSkipL2().build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        (bool open, bool executed, OptimisticTokenVotingPlugin.ProposalParameters memory parameters,,,,) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, true, "Open should be true");
        assertEq(executed, false, "Executed should be false");
        assertEq(parameters.unavailableL2, true, "unavailableL2 should be true");
        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal should not be executable");

        // Ended
        vm.warp(block.timestamp + 4 days);
        assertEq(optimisticPlugin.canExecute(proposalId), true, "The proposal should be executable");

        (open, executed, parameters,,,,) = optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "Open should be false");
        assertEq(executed, false, "Executed should be false");
        assertEq(parameters.unavailableL2, true, "unavailableL2 should be true");

        // Grace period almost over
        vm.warp(block.timestamp + builder.l2AggregationGracePeriod() - 1);
        assertEq(optimisticPlugin.canExecute(proposalId), true, "The proposal should be executable");

        // Grace period over
        vm.warp(block.timestamp + 1);
        assertEq(optimisticPlugin.canExecute(proposalId), true, "The proposal should be executable");

        (open, executed, parameters,,,,) = optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "Open should be false");
        assertEq(executed, false, "Executed should be false");
        assertEq(parameters.unavailableL2, true, "unavailableL2 should be true");
    }

    function test_CanExecuteReturnsTrueOtherwise() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable yet");

        vm.warp(block.timestamp + 3 days);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable yet");

        vm.warp(block.timestamp + 1 days - 1);

        assertEq(optimisticPlugin.canExecute(proposalId), false, "The proposal shouldn't be executable yet");

        vm.warp(block.timestamp + 1);

        assertEq(optimisticPlugin.canExecute(proposalId), true, "The proposal should be executable");
    }

    // Veto threshold reached
    function test_IsMinVetoRatioReachedReturnsTheAppropriateValuesOnlyL1Tokens() public {
        (dao, optimisticPlugin,,, votingToken, taikoL1) = builder.withMinVetoRatio(250_000).withTokenHolder(
            alice, 24 ether
        ).withTokenHolder(bob, 1 ether).withTokenHolder(randomWallet, 75 ether).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");
        // Alice vetoes 24%
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");

        vm.startPrank(bob);

        // Bob vetoes +1% => met
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), true, "The veto threshold should be met");

        vm.startPrank(randomWallet);

        // Random wallet vetoes +75% => still met
        optimisticPlugin.veto(proposalId);

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), true, "The veto threshold should still be met");
    }

    function test_IsMinVetoRatioReachedReturnsTheAppropriateValuesWithL1L2Tokens() public {
        // 200/300 vs 200/400 scenario
        builder = new DaoBuilder();
        (, optimisticPlugin,,,,) = builder.withOkTaikoL1().withMinVetoRatio(510_000).withTokenHolder(alice, 100 ether)
            .withTokenHolder(bob, 100 ether).withTokenHolder(carol, 100 ether).withTokenHolder(taikoBridge, 100 ether).build(
        );

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);
        (,, OptimisticTokenVotingPlugin.ProposalParameters memory parameters,,,,) =
            optimisticPlugin.getProposal(proposalId);
        assertEq(parameters.unavailableL2, false, "L2 should not be active");

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");
        optimisticPlugin.veto(proposalId); // Alice
        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId); // Bob (100+100 over 400 is 50%, below required 51%)

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met yet");
        vm.startPrank(carol);
        optimisticPlugin.veto(proposalId); // Carol (100+100+100 over 400 is 75%, above 51%)

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), true, "The veto threshold should be met now");

        // L2 paused
        vm.startPrank(alice);
        (, optimisticPlugin,,,,) = builder.withPausedTaikoL1().build();

        proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);
        (,, parameters,,,,) = optimisticPlugin.getProposal(proposalId);

        assertEq(parameters.unavailableL2, true, "L2 should be skipped");

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");
        optimisticPlugin.veto(proposalId); // Alice
        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId); // Bob (100+100 over 300 is 66.7%, above the required 51%)

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), true, "The veto threshold should be met now");

        vm.startPrank(carol);
        optimisticPlugin.veto(proposalId); // Carol
        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), true, "The veto threshold should be met now");

        // L2 out of sync
        vm.startPrank(alice);
        (, optimisticPlugin,,,,) = builder.withOutOfSyncTaikoL1().build();

        proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);
        (,, parameters,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(parameters.unavailableL2, true, "L2 should be skipped");

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");
        optimisticPlugin.veto(proposalId); // Alice
        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), false, "The veto threshold shouldn't be met");
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId); // Bob (100+100 over 300 is 66.7%, above the required 51%)

        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), true, "The veto threshold should be met now");

        vm.startPrank(carol);
        optimisticPlugin.veto(proposalId); // Carol
        assertEq(optimisticPlugin.isMinVetoRatioReached(proposalId), true, "The veto threshold should be met now");
    }

    // Execute
    function testFuzz_ExecuteRevertsWhenNotCreated(uint256 randomProposalId) public {
        vm.warp(0);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, randomProposalId)
        );
        optimisticPlugin.execute(randomProposalId);

        (, bool executed,,,,,) = optimisticPlugin.getProposal(randomProposalId);
        assertEq(executed, false, "The proposal should not be executed");

        // 2
        vm.warp(10 days);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, randomProposalId)
        );
        optimisticPlugin.execute(randomProposalId);

        (, executed,,,,,) = optimisticPlugin.getProposal(randomProposalId);
        assertEq(executed, false, "The proposal should not be executed");
    }

    function test_ExecuteRevertsWhenNotEnded() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        (, bool executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, false, "The proposal should not be executed");

        vm.warp(block.timestamp + 4 days);
        optimisticPlugin.execute(proposalId);

        (, executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, true, "The proposal should be executed");
    }

    function test_ExecuteRevertsWhenDefeatedOnlyL1Tokens() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        optimisticPlugin.veto(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        (, bool executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, false, "The proposal should not be executed");

        vm.warp(block.timestamp + 4 days);

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        (, executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, false, "The proposal should not be executed");
    }

    function test_ExecuteRevertsWhenDefeatedWithL1L2Tokens() public {
        vm.skip(true); // L2 aggregation still not available

        OptimisticTokenVotingPlugin.ProposalParameters memory parameters;

        // 70% min veto ratio
        // 2 vetoes required when L1 only
        // 3 vetoes required when L1+L2

        (, optimisticPlugin,,,,) = builder.withTokenHolder(alice, 10 ether).withTokenHolder(bob, 10 ether)
            .withTokenHolder(taikoBridge, 10 ether).withMinVetoRatio(700_000).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        (,, parameters,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(parameters.unavailableL2, false, "Should not skip the L2 census");

        optimisticPlugin.veto(proposalId); // 33%
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId); // 66% (below 70%)
        // bridge supply counts but doesn't veto

        vm.warp(block.timestamp + 4 days); // end
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);
        // ok
        vm.warp(block.timestamp + builder.l2AggregationGracePeriod()); // grace period over
        optimisticPlugin.execute(proposalId);

        // L2 paused, less token supply
        // Alice and Bob are now 100%

        (, optimisticPlugin,,,,) = builder.withPausedTaikoL1().build();

        proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        (,, parameters,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(parameters.unavailableL2, true, "Should skip the L2 census");

        optimisticPlugin.veto(proposalId); // 50%
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId); // 100% (above 70%)

        vm.warp(block.timestamp + 4 days); // end
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        vm.warp(block.timestamp + builder.l2AggregationGracePeriod()); // grace period over
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        // L2 out of sync, less token supply
        // Alice and Bob are now 100%

        (, optimisticPlugin,,,,) = builder.withOutOfSyncTaikoL1().build();

        proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        (,, parameters,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(parameters.unavailableL2, true, "Should skip the L2 census");

        optimisticPlugin.veto(proposalId); // 50%
        vm.startPrank(bob);
        optimisticPlugin.veto(proposalId); // 100% (above 70%)

        vm.warp(block.timestamp + 4 days); // end
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        vm.warp(block.timestamp + builder.l2AggregationGracePeriod()); // grace period over
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);
    }

    function test_ExecuteRevertsWhenAlreadyExecuted() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        vm.warp(block.timestamp + 4 days);

        optimisticPlugin.execute(proposalId);

        (, bool executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, true, "The proposal should be executed");

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        (, executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, true, "The proposal should be executed");
    }

    function test_ExecuteRevertsWhenEndedButL2GracePeriodUnmet() public {
        // An ended proposal with L2 enabled has an additional grace period

        (, optimisticPlugin,,,,) =
            builder.withTokenHolder(alice, 10 ether).withTokenHolder(taikoBridge, 10 ether).build();

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        (bool open, bool executed, OptimisticTokenVotingPlugin.ProposalParameters memory parameters,,,,) =
            optimisticPlugin.getProposal(proposalId);

        assertEq(open, true, "Open should be true");
        assertEq(executed, false, "Executed should be false");
        assertEq(parameters.unavailableL2, false, "unavailableL2 should be false");

        // ended
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        (open, executed, parameters,,,,) = optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "Open should be false");
        assertEq(executed, false, "Executed should be false");
        assertEq(parameters.unavailableL2, false, "unavailableL2 should be false");

        // Grace period almost over
        vm.warp(block.timestamp + builder.l2AggregationGracePeriod() - 1);
        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPlugin.ProposalExecutionForbidden.selector, proposalId)
        );
        optimisticPlugin.execute(proposalId);

        (open, executed, parameters,,,,) = optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "Open should be false");
        assertEq(executed, false, "Executed should be false");
        assertEq(parameters.unavailableL2, false, "unavailableL2 should be false");

        // Grace period over
        vm.warp(block.timestamp + 1);
        optimisticPlugin.execute(proposalId);

        (open, executed, parameters,,,,) = optimisticPlugin.getProposal(proposalId);

        assertEq(open, false, "Open should be false");
        assertEq(executed, true, "Executed should be true");
        assertEq(parameters.unavailableL2, false, "unavailableL2 should be false");
    }

    function test_ExecuteSucceedsOtherwise() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        vm.warp(block.timestamp + 4 days);

        optimisticPlugin.execute(proposalId);
    }

    function test_ExecuteMarksTheProposalAsExecuted() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        (, bool executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, false, "The proposal should not be executed");

        vm.warp(block.timestamp + 4 days);

        (, executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, false, "The proposal should not be executed");

        optimisticPlugin.execute(proposalId);

        (, executed,,,,,) = optimisticPlugin.getProposal(proposalId);
        assertEq(executed, true, "The proposal should be executed");
    }

    function test_ExecuteEmitsAnEvent() public {
        IDAO.Action[] memory actions = new IDAO.Action[](0);
        uint256 proposalId = optimisticPlugin.createProposal("ipfs://", actions, 0, 4 days);

        vm.warp(block.timestamp + 4 days);

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
            l2AggregationGracePeriod: 2 days,
            skipL2: false
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
            l2AggregationGracePeriod: 2 days,
            skipL2: false
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
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });
        vm.expectRevert(abi.encodeWithSelector(RatioOutOfBounds.selector, RATIO_BASE, uint32(RATIO_BASE + 1)));
        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_UpdateOptimisticGovernanceSettingsRevertsWhenTheMinDurationIsMoreThanOneYear() public {
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory newSettings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 365 days + 1,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
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
            l2AggregationGracePeriod: 2 days,
            skipL2: false
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
            l2AggregationGracePeriod: 2 days,
            skipL2: false
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
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });

        vm.expectEmit();
        emit OptimisticGovernanceSettingsUpdated({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 15 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });

        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);

        // 2

        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 19 days,
            l2InactivityPeriod: 50 minutes,
            l2AggregationGracePeriod: 20 days,
            skipL2: true
        });

        vm.warp(block.timestamp + 1);

        vm.expectEmit();
        emit OptimisticGovernanceSettingsUpdated({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 19 days,
            l2InactivityPeriod: 50 minutes,
            l2AggregationGracePeriod: 20 days,
            skipL2: true
        });

        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);
    }

    function test_GovernanceSettingsReturnsTheRightValues() public {
        (
            uint32 minVetoRatio,
            uint64 minDuration,
            uint64 l2InactivityPeriod,
            uint64 l2AggregationGracePeriod,
            bool skipL2
        ) = optimisticPlugin.governanceSettings();

        assertEq(minVetoRatio, uint32(RATIO_BASE / 10));
        assertEq(minDuration, 4 days);
        assertEq(l2InactivityPeriod, 10 minutes);
        assertEq(l2AggregationGracePeriod, 2 days);
        assertEq(skipL2, false);

        // Deploy a new optimisticPlugin instance
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory newSettings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 2),
            minDuration: 0,
            l2InactivityPeriod: 15 minutes,
            l2AggregationGracePeriod: 73 days,
            skipL2: true
        });

        optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize,
                    (dao, newSettings, votingToken, address(taikoL1), taikoBridge)
                )
            )
        );

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(minVetoRatio, uint32(RATIO_BASE / 2));
        assertEq(minDuration, 0);
        assertEq(l2InactivityPeriod, 15 minutes);
        assertEq(l2AggregationGracePeriod, 73 days);
        assertEq(skipL2, true);

        // updated settings
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );

        newSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 15 days,
            l2InactivityPeriod: 0,
            l2AggregationGracePeriod: 1234 minutes,
            skipL2: false
        });

        optimisticPlugin.updateOptimisticGovernanceSettings(newSettings);

        (minVetoRatio, minDuration, l2InactivityPeriod, l2AggregationGracePeriod, skipL2) =
            optimisticPlugin.governanceSettings();
        assertEq(minVetoRatio, uint32(RATIO_BASE / 5));
        assertEq(minDuration, 15 days);
        assertEq(l2InactivityPeriod, 0);
        assertEq(l2AggregationGracePeriod, 1234 minutes);
        assertEq(skipL2, false);
    }

    // Upgrade optimisticPlugin
    function test_UpgradeToRevertsWhenCalledFromNonUpgrader() public {
        address initialImplementation = optimisticPlugin.implementation();

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

        assertEq(
            optimisticPlugin.implementation(), initialImplementation, "Should still have the initial implementation"
        );
    }

    function test_UpgradeToAndCallRevertsWhenCalledFromNonUpgrader() public {
        address initialImplementation = optimisticPlugin.implementation();

        // We need to call something: preparing new settings
        dao.grant(
            address(optimisticPlugin), alice, optimisticPlugin.UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID()
        );
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 15 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });

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
        optimisticPlugin.upgradeToAndCall(
            _newImplementation,
            abi.encodeCall(OptimisticTokenVotingPlugin.updateOptimisticGovernanceSettings, (settings))
        );

        assertEq(optimisticPlugin.implementation(), initialImplementation);
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
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });
        optimisticPlugin.upgradeToAndCall(
            _newImplementation,
            abi.encodeCall(OptimisticTokenVotingPlugin.updateOptimisticGovernanceSettings, (settings))
        );

        assertEq(optimisticPlugin.implementation(), address(_newImplementation));
    }
}
