// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {OptimisticTokenVotingPluginSetup} from "../src/setup/OptimisticTokenVotingPluginSetup.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ITaikoL1} from "../src/adapted-dependencies/ITaikoL1.sol";

contract OptimisticTokenVotingPluginSetupTest is Test {
    OptimisticTokenVotingPluginSetup public pluginSetup;
    GovernanceERC20 governanceERC20Base;
    GovernanceWrappedERC20 governanceWrappedERC20Base;
    address immutable daoBase = address(new DAO());
    DAO dao;

    // Recycled installation parameters
    OptimisticTokenVotingPlugin.OptimisticGovernanceSettings votingSettings;
    OptimisticTokenVotingPluginSetup.TokenSettings tokenSettings;
    GovernanceERC20.MintSettings mintSettings;
    ITaikoL1 taikoL1;
    address taikoBridge;
    uint64 stdProposalMinDuration;
    address stdProposer;
    address emergencyProposer;

    address alice = address(0xa11ce);

    error Unimplemented();

    function setUp() public {
        if (address(governanceERC20Base) == address(0x0)) {
            // Base
            GovernanceERC20.MintSettings memory _mintSettings =
                GovernanceERC20.MintSettings(new address[](0), new uint256[](0));
            governanceERC20Base = new GovernanceERC20(IDAO(address(0x0)), "", "", _mintSettings);
            // Base
            governanceWrappedERC20Base = new GovernanceWrappedERC20(IERC20Upgradeable(address(0x0)), "", "");
            dao = DAO(
                payable(
                    createProxyAndCall(address(daoBase), abi.encodeCall(DAO.initialize, ("", alice, address(0x0), "")))
                )
            );
        }

        pluginSetup = new OptimisticTokenVotingPluginSetup(governanceERC20Base, governanceWrappedERC20Base);

        // Default params
        votingSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 5 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });
        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({
            addr: address(governanceERC20Base),
            name: "Wrapped Token",
            symbol: "wTK"
        });
        mintSettings = GovernanceERC20.MintSettings({receivers: new address[](0), amounts: new uint256[](0)});
        taikoL1 = ITaikoL1(address(0x66666666));
        taikoBridge = address(0x55555555);
        stdProposalMinDuration = 10 days;
        stdProposer = address(0x1234567890);
        emergencyProposer = address(0x2345678901);
    }

    function test_ConstructorShouldDefineTheRightValues() public {
        setUp();

        assertEq(pluginSetup.implementation() != address(0), true);
        assertEq(pluginSetup.governanceERC20Base(), address(governanceERC20Base), "Address should be equal");
        assertEq(
            pluginSetup.governanceWrappedERC20Base(), address(governanceWrappedERC20Base), "Address should be equal"
        );
    }

    function test_ShouldEncodeInstallationParams_Default() public view {
        // Default
        bytes memory output = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        bytes memory expected =
            hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000186a000000000000000000000000000000000000000000000000000000000000697800000000000000000000000000000000000000000000000000000000000000258000000000000000000000000000000000000000000000000000000000002a3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000066666666000000000000000000000000000000000000000000000000000000005555555500000000000000000000000000000000000000000000000000000000000d2f00000000000000000000000000000000000000000000000000000000123456789000000000000000000000000000000000000000000000000000000023456789010000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000d5772617070656420546f6b656e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000377544b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldEncodeInstallationParams_1() public {
        // Custom 1
        votingSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 60 * 60 * 24 * 5,
            l2InactivityPeriod: 20 minutes,
            l2AggregationGracePeriod: 20 days,
            skipL2: false
        });
        bytes memory output = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        bytes memory expected =
            hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000030d40000000000000000000000000000000000000000000000000000000000006978000000000000000000000000000000000000000000000000000000000000004b000000000000000000000000000000000000000000000000000000000001a5e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000066666666000000000000000000000000000000000000000000000000000000005555555500000000000000000000000000000000000000000000000000000000000d2f00000000000000000000000000000000000000000000000000000000123456789000000000000000000000000000000000000000000000000000000023456789010000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000d5772617070656420546f6b656e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000377544b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        assertEq(output, expected, "Incorrect encoded bytes");

        // Custom 2 (skip L2)
        votingSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 60 * 60 * 24 * 5,
            l2InactivityPeriod: 20 minutes,
            l2AggregationGracePeriod: 20 days,
            skipL2: true
        });
        output = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        expected =
            hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000030d40000000000000000000000000000000000000000000000000000000000006978000000000000000000000000000000000000000000000000000000000000004b000000000000000000000000000000000000000000000000000000000001a5e000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000066666666000000000000000000000000000000000000000000000000000000005555555500000000000000000000000000000000000000000000000000000000000d2f00000000000000000000000000000000000000000000000000000000123456789000000000000000000000000000000000000000000000000000000023456789010000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000d5772617070656420546f6b656e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000377544b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldEncodeInstallationParams_2() public {
        // Custom 2
        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({
            addr: address(0x5678),
            name: "Wrapped New Coin",
            symbol: "wNCN"
        });
        bytes memory output = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        bytes memory expected =
            hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000186a000000000000000000000000000000000000000000000000000000000000697800000000000000000000000000000000000000000000000000000000000000258000000000000000000000000000000000000000000000000000000000002a3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000066666666000000000000000000000000000000000000000000000000000000005555555500000000000000000000000000000000000000000000000000000000000d2f00000000000000000000000000000000000000000000000000000000123456789000000000000000000000000000000000000000000000000000000023456789010000000000000000000000000000000000000000000000000000000000005678000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000001057726170706564204e657720436f696e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004774e434e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldEncodeInstallationParams_3() public {
        // Custom 3
        address[] memory receivers = new address[](1);
        receivers[0] = address(0x6789);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1234567890;

        mintSettings = GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts});
        bytes memory output = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(0x1234),
                address(0x5678), // taikoBridge
                5 days, // stdProposalMinDuration
                stdProposer,
                emergencyProposer
            )
        );

        bytes memory expected =
            hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000186a000000000000000000000000000000000000000000000000000000000000697800000000000000000000000000000000000000000000000000000000000000258000000000000000000000000000000000000000000000000000000000002a300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000260000000000000000000000000000000000000000000000000000000000000123400000000000000000000000000000000000000000000000000000000000056780000000000000000000000000000000000000000000000000000000000069780000000000000000000000000000000000000000000000000000000123456789000000000000000000000000000000000000000000000000000000023456789010000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000d5772617070656420546f6b656e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000377544b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000006789000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000499602d2";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldEncodeInstallationParams_4() public {
        // Custom 4
        stdProposer = address(0x567890);

        bytes memory output = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(0x1111),
                address(0x2222), // taikoBridge
                15 days, // stdProposalMinDuration
                stdProposer,
                emergencyProposer
            )
        );

        bytes memory expected =
            hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000186a000000000000000000000000000000000000000000000000000000000000697800000000000000000000000000000000000000000000000000000000000000258000000000000000000000000000000000000000000000000000000000002a30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000011110000000000000000000000000000000000000000000000000000000000002222000000000000000000000000000000000000000000000000000000000013c680000000000000000000000000000000000000000000000000000000000056789000000000000000000000000000000000000000000000000000000023456789010000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000d5772617070656420546f6b656e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000377544b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        assertEq(output, expected, "Incorrect encoded bytes");
    }

    function test_ShouldDecodeInstallationParams_1() public {
        votingSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 4),
            minDuration: 10 days,
            l2InactivityPeriod: 22 minutes,
            l2AggregationGracePeriod: 24 days,
            skipL2: false
        });
        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({
            addr: address(governanceWrappedERC20Base),
            name: "Super wToken",
            symbol: "SwTK"
        });
        address[] memory receivers = new address[](2);
        receivers[0] = address(0x1234);
        receivers[1] = address(0x5678);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2000;
        amounts[1] = 5000;
        mintSettings = GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts});
        stdProposalMinDuration = 6 days;
        stdProposer = address(0x3456);
        emergencyProposer = address(0x7890);

        bytes memory _installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                // only used for GovernanceERC20 (when a token is not passed)
                mintSettings,
                address(0x9999),
                address(0xaaaa),
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        // Decode
        OptimisticTokenVotingPluginSetup.InstallationParameters memory _decodedInstallationParams =
            pluginSetup.decodeInstallationParams(_installationParams);

        // Voting
        assertEq(
            _decodedInstallationParams.votingSettings.minVetoRatio, uint32(RATIO_BASE / 4), "Incorrect minVetoRatio"
        );
        assertEq(_decodedInstallationParams.votingSettings.minDuration, 10 days, "Incorrect minDuration");
        assertEq(
            _decodedInstallationParams.votingSettings.l2InactivityPeriod, 22 minutes, "Incorrect l2InactivityPeriod"
        );
        assertEq(
            _decodedInstallationParams.votingSettings.l2AggregationGracePeriod,
            24 days,
            "Incorrect l2AggregationGracePeriod"
        );

        // Token
        assertEq(
            _decodedInstallationParams.tokenSettings.addr,
            address(governanceWrappedERC20Base),
            "Incorrect token address"
        );
        assertEq(_decodedInstallationParams.tokenSettings.name, "Super wToken", "Incorrect token address");
        assertEq(_decodedInstallationParams.tokenSettings.symbol, "SwTK", "Incorrect token address");

        // Mint
        assertEq(_decodedInstallationParams.mintSettings.receivers.length, 2, "Incorrect receivers.length");
        assertEq(_decodedInstallationParams.mintSettings.receivers[0], address(0x1234), "Incorrect receivers[0]");
        assertEq(_decodedInstallationParams.mintSettings.receivers[1], address(0x5678), "Incorrect receivers[1]");
        assertEq(_decodedInstallationParams.mintSettings.amounts.length, 2, "Incorrect amounts.length");
        assertEq(_decodedInstallationParams.mintSettings.amounts[0], 2000, "Incorrect amounts[0]");
        assertEq(_decodedInstallationParams.mintSettings.amounts[1], 5000, "Incorrect amounts[1]");

        // Taiko contracts
        assertEq(address(_decodedInstallationParams.taikoL1), address(0x9999), "Incorrect taikoL1");
        assertEq(address(_decodedInstallationParams.taikoBridge), address(0xaaaa), "Incorrect taikoBridge");

        // Proposals
        assertEq(_decodedInstallationParams.stdProposalMinDuration, 6 days, "Incorrect stdProposalMinDuration");
        assertEq(_decodedInstallationParams.stdProposer, address(0x3456), "Incorrect standard proposer");
        assertEq(_decodedInstallationParams.emergencyProposer, address(0x7890), "Incorrect emergency proposer");
    }

    function test_ShouldDecodeInstallationParams_2() public {
        votingSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 5),
            minDuration: 12 days,
            l2InactivityPeriod: 44 minutes,
            l2AggregationGracePeriod: 45 days,
            skipL2: true
        });
        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({
            addr: address(governanceWrappedERC20Base),
            name: "Mega wToken",
            symbol: "MwTK"
        });
        address[] memory receivers = new address[](4);
        receivers[0] = address(0x1111);
        receivers[1] = address(0x2222);
        receivers[2] = address(0x3333);
        receivers[3] = address(0x4444);
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1000;
        amounts[1] = 2000;
        amounts[2] = 3000;
        amounts[3] = 4000;
        mintSettings = GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts});
        stdProposalMinDuration = 9 days;
        stdProposer = address(0x6666);
        emergencyProposer = address(0x8888);

        bytes memory _installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                // only used for GovernanceERC20 (when a token is not passed)
                mintSettings,
                address(0xbbbb),
                address(0xcccc),
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        // Decode
        OptimisticTokenVotingPluginSetup.InstallationParameters memory _decodedInstallationParams =
            pluginSetup.decodeInstallationParams(_installationParams);

        // Voting
        assertEq(
            _decodedInstallationParams.votingSettings.minVetoRatio, uint32(RATIO_BASE / 5), "Incorrect minVetoRatio"
        );
        assertEq(_decodedInstallationParams.votingSettings.minDuration, 12 days, "Incorrect minDuration");
        assertEq(
            _decodedInstallationParams.votingSettings.l2InactivityPeriod, 44 minutes, "Incorrect l2InactivityPeriod"
        );
        assertEq(
            _decodedInstallationParams.votingSettings.l2AggregationGracePeriod,
            45 days,
            "Incorrect l2AggregationGracePeriod"
        );

        // Token
        assertEq(
            _decodedInstallationParams.tokenSettings.addr,
            address(governanceWrappedERC20Base),
            "Incorrect token address"
        );
        assertEq(_decodedInstallationParams.tokenSettings.name, "Mega wToken", "Incorrect token address");
        assertEq(_decodedInstallationParams.tokenSettings.symbol, "MwTK", "Incorrect token address");

        // Mint
        assertEq(_decodedInstallationParams.mintSettings.receivers.length, 4, "Incorrect receivers.length");
        assertEq(_decodedInstallationParams.mintSettings.receivers[0], address(0x1111), "Incorrect receivers[0]");
        assertEq(_decodedInstallationParams.mintSettings.receivers[1], address(0x2222), "Incorrect receivers[1]");
        assertEq(_decodedInstallationParams.mintSettings.receivers[2], address(0x3333), "Incorrect receivers[2]");
        assertEq(_decodedInstallationParams.mintSettings.receivers[3], address(0x4444), "Incorrect receivers[3]");
        assertEq(_decodedInstallationParams.mintSettings.amounts.length, 4, "Incorrect amounts.length");
        assertEq(_decodedInstallationParams.mintSettings.amounts[0], 1000, "Incorrect amounts[0]");
        assertEq(_decodedInstallationParams.mintSettings.amounts[1], 2000, "Incorrect amounts[1]");
        assertEq(_decodedInstallationParams.mintSettings.amounts[2], 3000, "Incorrect amounts[2]");
        assertEq(_decodedInstallationParams.mintSettings.amounts[3], 4000, "Incorrect amounts[3]");

        // Taiko contracts
        assertEq(address(_decodedInstallationParams.taikoL1), address(0xbbbb), "Incorrect taikoL1");
        assertEq(address(_decodedInstallationParams.taikoBridge), address(0xcccc), "Incorrect taikoBridge");

        // Proposal
        assertEq(_decodedInstallationParams.stdProposalMinDuration, 9 days, "Incorrect stdProposalMinDuration");
        assertEq(_decodedInstallationParams.stdProposer, address(0x6666), "Incorrect standard proposer");
        assertEq(_decodedInstallationParams.emergencyProposer, address(0x8888), "Incorrect emergency proposer");
    }

    function test_PrepareInstallationReturnsTheProperPermissions_Default() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                // only used for GovernanceERC20 (when a token is not passed)
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        (address _plugin, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        assertEq(_plugin != address(0), true, "Plugin address should not be zero");
        assertEq(_preparedSetupData.helpers.length, 1, "One helper expected");
        assertEq(
            _preparedSetupData.permissions.length,
            5, // base + 2 proposers
            "Incorrect permission length"
        );
        // 1
        assertEq(
            uint256(_preparedSetupData.permissions[0].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[0].where, _plugin);
        assertEq(_preparedSetupData.permissions[0].who, address(dao));
        assertEq(_preparedSetupData.permissions[0].condition, address(0));
        assertEq(
            _preparedSetupData.permissions[0].permissionId,
            keccak256("UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION")
        );
        // 2
        assertEq(
            uint256(_preparedSetupData.permissions[1].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[1].where, _plugin);
        assertEq(_preparedSetupData.permissions[1].who, address(dao));
        assertEq(_preparedSetupData.permissions[1].condition, address(0));
        assertEq(_preparedSetupData.permissions[1].permissionId, keccak256("UPGRADE_PLUGIN_PERMISSION"));
        // 3
        assertEq(
            uint256(_preparedSetupData.permissions[2].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[2].where, address(dao));
        assertEq(_preparedSetupData.permissions[2].who, _plugin);
        assertEq(_preparedSetupData.permissions[2].condition, address(0));
        assertEq(_preparedSetupData.permissions[2].permissionId, keccak256("EXECUTE_PERMISSION"));
        // proposer 1
        assertEq(
            uint256(_preparedSetupData.permissions[3].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[3].where, _plugin);
        assertEq(_preparedSetupData.permissions[3].who, address(stdProposer));
        assertNotEq(_preparedSetupData.permissions[3].condition, address(0));
        assertEq(_preparedSetupData.permissions[3].permissionId, keccak256("PROPOSER_PERMISSION"));
        // proposer 2
        assertEq(
            uint256(_preparedSetupData.permissions[4].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[4].where, _plugin);
        assertEq(_preparedSetupData.permissions[4].who, address(emergencyProposer));
        assertEq(_preparedSetupData.permissions[4].condition, address(0));
        assertEq(_preparedSetupData.permissions[4].permissionId, keccak256("PROPOSER_PERMISSION"));

        // no more: no minted token
    }

    function test_PrepareInstallationReturnsTheProperPermissions_UseToken() public {
        votingSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 4),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });
        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({
            addr: address(governanceWrappedERC20Base),
            name: "",
            symbol: ""
        });
        stdProposer = address(0x3456);
        emergencyProposer = address(0x7890);

        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                // only used for GovernanceERC20 (when a token is not passed)
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        (address _plugin, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        assertEq(_plugin != address(0), true, "Plugin address should not be zero");
        assertEq(_preparedSetupData.helpers.length, 1, "One helper expected");
        assertEq(
            _preparedSetupData.permissions.length,
            3 + 2, // base + 2 proposers
            "Incorrect permission length"
        );
        // 1
        assertEq(
            uint256(_preparedSetupData.permissions[0].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[0].where, _plugin);
        assertEq(_preparedSetupData.permissions[0].who, address(dao));
        assertEq(_preparedSetupData.permissions[0].condition, address(0));
        assertEq(
            _preparedSetupData.permissions[0].permissionId,
            keccak256("UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION")
        );
        // 2
        assertEq(
            uint256(_preparedSetupData.permissions[1].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[1].where, _plugin);
        assertEq(_preparedSetupData.permissions[1].who, address(dao));
        assertEq(_preparedSetupData.permissions[1].condition, address(0));
        assertEq(_preparedSetupData.permissions[1].permissionId, keccak256("UPGRADE_PLUGIN_PERMISSION"));
        // 3
        assertEq(
            uint256(_preparedSetupData.permissions[2].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[2].where, address(dao));
        assertEq(_preparedSetupData.permissions[2].who, _plugin);
        assertEq(_preparedSetupData.permissions[2].condition, address(0));
        assertEq(_preparedSetupData.permissions[2].permissionId, keccak256("EXECUTE_PERMISSION"));
        // proposer 1
        assertEq(
            uint256(_preparedSetupData.permissions[3].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[3].where, _plugin);
        assertEq(_preparedSetupData.permissions[3].who, address(stdProposer));
        assertNotEq(_preparedSetupData.permissions[3].condition, address(0));
        assertEq(_preparedSetupData.permissions[3].permissionId, keccak256("PROPOSER_PERMISSION"));
        // proposer 2
        assertEq(
            uint256(_preparedSetupData.permissions[4].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[4].where, _plugin);
        assertEq(_preparedSetupData.permissions[4].who, address(emergencyProposer));
        assertEq(_preparedSetupData.permissions[4].condition, address(0));
        assertEq(_preparedSetupData.permissions[4].permissionId, keccak256("PROPOSER_PERMISSION"));

        // no more: no minted token
    }

    function test_PrepareInstallationReturnsTheProperPermissions_MintToken() public {
        votingSettings = OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 4),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days,
            skipL2: false
        });
        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({
            addr: address(0x0),
            name: "Wrapped Super New Token",
            symbol: "wSNTK"
        });
        address[] memory receivers = new address[](2);
        receivers[0] = address(0x1234);
        receivers[1] = address(0x5678);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2000;
        amounts[1] = 5000;
        mintSettings = GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts});
        stdProposer = address(0x3456);
        emergencyProposer = address(0x7890);

        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                // only used for GovernanceERC20 (when a token is not passed)
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        (address _plugin, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        assertEq(_plugin != address(0), true, "Plugin address should not be zero");
        assertEq(_preparedSetupData.helpers.length, 1, "One helper expected");
        assertEq(
            _preparedSetupData.permissions.length,
            3 + 2 + 1, // base + proposers
            "Incorrect permission length"
        );
        // 1
        assertEq(
            uint256(_preparedSetupData.permissions[0].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[0].where, _plugin);
        assertEq(_preparedSetupData.permissions[0].who, address(dao));
        assertEq(_preparedSetupData.permissions[0].condition, address(0));
        assertEq(
            _preparedSetupData.permissions[0].permissionId,
            keccak256("UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION")
        );
        // 2
        assertEq(
            uint256(_preparedSetupData.permissions[1].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[1].where, _plugin);
        assertEq(_preparedSetupData.permissions[1].who, address(dao));
        assertEq(_preparedSetupData.permissions[1].condition, address(0));
        assertEq(_preparedSetupData.permissions[1].permissionId, keccak256("UPGRADE_PLUGIN_PERMISSION"));
        // 3
        assertEq(
            uint256(_preparedSetupData.permissions[2].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[2].where, address(dao));
        assertEq(_preparedSetupData.permissions[2].who, _plugin);
        assertEq(_preparedSetupData.permissions[2].condition, address(0));
        assertEq(_preparedSetupData.permissions[2].permissionId, keccak256("EXECUTE_PERMISSION"));
        // proposer 1
        assertEq(
            uint256(_preparedSetupData.permissions[3].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[3].where, _plugin);
        assertEq(_preparedSetupData.permissions[3].who, address(stdProposer));
        assertNotEq(_preparedSetupData.permissions[3].condition, address(0));
        assertEq(_preparedSetupData.permissions[3].permissionId, keccak256("PROPOSER_PERMISSION"));
        // proposer 2
        assertEq(
            uint256(_preparedSetupData.permissions[4].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[4].where, _plugin);
        assertEq(_preparedSetupData.permissions[4].who, address(emergencyProposer));
        assertEq(_preparedSetupData.permissions[4].condition, address(0));
        assertEq(_preparedSetupData.permissions[4].permissionId, keccak256("PROPOSER_PERMISSION"));

        // minting
        assertEq(
            uint256(_preparedSetupData.permissions[5].operation),
            uint256(PermissionLib.Operation.Grant),
            "Incorrect operation"
        );
        assertEq(_preparedSetupData.permissions[5].where, _preparedSetupData.helpers[0]);
        assertEq(_preparedSetupData.permissions[5].who, address(dao));
        assertEq(_preparedSetupData.permissions[5].condition, address(0));
        assertEq(_preparedSetupData.permissions[5].permissionId, keccak256("MINT_PERMISSION"));
    }

    function test_PrepareInstallationWithNonContractTokenReverts() public {
        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({
            addr: address(1234),
            name: "Non-contract address",
            symbol: "abc"
        });
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                // only used for GovernanceERC20 (when a token is not passed)
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(OptimisticTokenVotingPluginSetup.TokenNotContract.selector, address(1234))
        );
        pluginSetup.prepareInstallation(address(dao), installationParams);
    }

    function test_PrepareInstallationWithNonErc20TokenReverts() public {
        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({
            addr: address(dao),
            name: "Non-ERC20 address",
            symbol: "abc"
        });
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                // only used for GovernanceERC20 (when a token is not passed)
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPluginSetup.TokenNotERC20.selector, address(dao)));
        pluginSetup.prepareInstallation(address(dao), installationParams);
    }

    function test_PrepareUninstallationReturnsTheProperPermissions_1() public {
        // Prepare a dummy install
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );
        (address _dummyPlugin, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        OptimisticTokenVotingPluginSetup.SetupPayload memory _payload =
            IPluginSetup.SetupPayload({plugin: _dummyPlugin, currentHelpers: _preparedSetupData.helpers, data: hex""});

        // Check uninstall
        PermissionLib.MultiTargetPermission[] memory _permissionChanges =
            pluginSetup.prepareUninstallation(address(dao), _payload);

        assertEq(_permissionChanges.length, 4, "Incorrect permission changes length");
        // 1
        assertEq(
            uint256(_permissionChanges[0].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[0].where, _dummyPlugin);
        assertEq(_permissionChanges[0].who, address(dao));
        assertEq(_permissionChanges[0].condition, address(0));
        assertEq(_permissionChanges[0].permissionId, keccak256("UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION"));
        // 2
        assertEq(
            uint256(_permissionChanges[1].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[1].where, _dummyPlugin);
        assertEq(_permissionChanges[1].who, address(dao));
        assertEq(_permissionChanges[1].condition, address(0));
        assertEq(_permissionChanges[1].permissionId, keccak256("UPGRADE_PLUGIN_PERMISSION"));
        // 3
        assertEq(
            uint256(_permissionChanges[2].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[2].where, address(dao));
        assertEq(_permissionChanges[2].who, _dummyPlugin);
        assertEq(_permissionChanges[2].condition, address(0));
        assertEq(_permissionChanges[2].permissionId, keccak256("EXECUTE_PERMISSION"));
        // minting 1
        assertEq(
            uint256(_permissionChanges[3].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[3].where, address(governanceERC20Base), "Incorrect where");
        assertEq(_permissionChanges[3].who, address(dao), "Incorrect who");
        assertEq(_permissionChanges[3].condition, address(0), "Incorrect condition");
        assertEq(_permissionChanges[3].permissionId, keccak256("MINT_PERMISSION"), "Incorrect permission");
    }

    function test_PrepareUninstallationReturnsTheProperPermissions_2() public {
        // Prepare a dummy install
        tokenSettings =
            OptimisticTokenVotingPluginSetup.TokenSettings({addr: address(0x0), name: "Dummy Token", symbol: "DTK"});
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );
        (address _dummyPlugin, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        OptimisticTokenVotingPluginSetup.SetupPayload memory _payload =
            IPluginSetup.SetupPayload({plugin: _dummyPlugin, currentHelpers: _preparedSetupData.helpers, data: hex""});

        // Check uninstall
        PermissionLib.MultiTargetPermission[] memory _permissionChanges =
            pluginSetup.prepareUninstallation(address(dao), _payload);

        assertEq(_permissionChanges.length, 4, "Incorrect permission changes length");
        // 1
        assertEq(
            uint256(_permissionChanges[0].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[0].where, _dummyPlugin);
        assertEq(_permissionChanges[0].who, address(dao));
        assertEq(_permissionChanges[0].condition, address(0));
        assertEq(_permissionChanges[0].permissionId, keccak256("UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION"));
        // 2
        assertEq(
            uint256(_permissionChanges[1].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[1].where, _dummyPlugin);
        assertEq(_permissionChanges[1].who, address(dao));
        assertEq(_permissionChanges[1].condition, address(0));
        assertEq(_permissionChanges[1].permissionId, keccak256("UPGRADE_PLUGIN_PERMISSION"));
        // 3
        assertEq(
            uint256(_permissionChanges[2].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[2].where, address(dao));
        assertEq(_permissionChanges[2].who, _dummyPlugin);
        assertEq(_permissionChanges[2].condition, address(0));
        assertEq(_permissionChanges[2].permissionId, keccak256("EXECUTE_PERMISSION"));
        // minting 1
        assertEq(
            uint256(_permissionChanges[3].operation), uint256(PermissionLib.Operation.Revoke), "Incorrect operation"
        );
        assertEq(_permissionChanges[3].where, _preparedSetupData.helpers[0], "Incorrect where");
        assertEq(_permissionChanges[3].who, address(dao), "Incorrect who");
        assertEq(_permissionChanges[3].condition, address(0), "Incorrect condition");
        assertEq(_permissionChanges[3].permissionId, keccak256("MINT_PERMISSION"), "Incorrect permission");
    }

    function test_PrepareUninstallationRevertsWithWrongHelpersLength() public {
        // 0

        // Prepare a dummy install
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );
        (address _dummyPlugin, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        _preparedSetupData.helpers = new address[](0);
        OptimisticTokenVotingPluginSetup.SetupPayload memory _payload =
            IPluginSetup.SetupPayload({plugin: _dummyPlugin, currentHelpers: _preparedSetupData.helpers, data: hex""});

        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPluginSetup.WrongHelpersArrayLength.selector, 0));
        pluginSetup.prepareUninstallation(address(dao), _payload);

        // 2

        // Prepare a dummy install
        installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );
        (_dummyPlugin, _preparedSetupData) = pluginSetup.prepareInstallation(address(dao), installationParams);

        _preparedSetupData.helpers = new address[](2);
        _payload =
            IPluginSetup.SetupPayload({plugin: _dummyPlugin, currentHelpers: _preparedSetupData.helpers, data: hex""});

        vm.expectRevert(abi.encodeWithSelector(OptimisticTokenVotingPluginSetup.WrongHelpersArrayLength.selector, 2));
        pluginSetup.prepareUninstallation(address(dao), _payload);
    }

    function test_CreatesANewERC20Token() public {
        // new Token
        tokenSettings =
            OptimisticTokenVotingPluginSetup.TokenSettings({addr: address(0x0), name: "New Token", symbol: "NTK"});

        address[] memory receivers = new address[](1);
        receivers[0] = address(0x1234);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;
        mintSettings = GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts});
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                // only used for GovernanceERC20 (when a token is not passed)
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );
        (, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        GovernanceERC20 _token = GovernanceERC20(_preparedSetupData.helpers[0]);
        assertEq(_token.balanceOf(address(0x1234)), 100);
        assertEq(_token.balanceOf(address(0x5678)), 0);
        assertEq(_token.balanceOf(address(0x0)), 0);

        assertEq(_token.name(), "New Token");
        assertEq(_token.symbol(), "NTK");
    }

    function test_WrapsAnExistingToken() public {
        // Wrap existing token
        ERC20Mock _originalToken = new ERC20Mock();
        _originalToken.mintTo(address(0x1234), 100);
        _originalToken.mintTo(address(0x5678), 200);
        assertEq(_originalToken.balanceOf(address(0x1234)), 100);
        assertEq(_originalToken.balanceOf(address(0x5678)), 200);

        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({
            addr: address(_originalToken),
            name: "Wrapped Mock Token",
            symbol: "wMTK"
        });
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );
        (, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        GovernanceWrappedERC20 _wrappedToken = GovernanceWrappedERC20(_preparedSetupData.helpers[0]);
        assertEq(_wrappedToken.balanceOf(address(0x1234)), 0);
        assertEq(_wrappedToken.balanceOf(address(0x5678)), 0);
        assertEq(_wrappedToken.balanceOf(address(0x0)), 0);

        assertEq(_wrappedToken.name(), "Wrapped Mock Token");
        assertEq(_wrappedToken.symbol(), "wMTK");

        vm.startPrank(address(0x1234));
        _originalToken.approve(address(_wrappedToken), 100);
        _wrappedToken.depositFor(address(0x1234), 100);

        vm.startPrank(address(0x5678));
        _originalToken.approve(address(_wrappedToken), 200);
        _wrappedToken.depositFor(address(0x5678), 200);

        assertEq(_wrappedToken.balanceOf(address(0x1234)), 100);
        assertEq(_wrappedToken.balanceOf(address(0x5678)), 200);
        assertEq(_wrappedToken.balanceOf(address(0x0)), 0);
    }

    function test_UsesAnExistingGovernanceERC20Token() public {
        // Use existing governance token
        address[] memory receivers = new address[](2);
        receivers[0] = address(0x1234);
        receivers[1] = address(0x5678);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;
        mintSettings = GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts});
        GovernanceERC20 _token = GovernanceERC20(
            payable(
                createProxyAndCall(
                    address(governanceERC20Base),
                    abi.encodeCall(GovernanceERC20.initialize, (IDAO(dao), "My Token", "MTK", mintSettings))
                )
            )
        );
        tokenSettings = OptimisticTokenVotingPluginSetup.TokenSettings({addr: address(_token), name: "", symbol: ""});
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            OptimisticTokenVotingPluginSetup.InstallationParameters(
                votingSettings,
                tokenSettings,
                mintSettings,
                address(taikoL1),
                taikoBridge,
                stdProposalMinDuration,
                stdProposer,
                emergencyProposer
            )
        );
        (, IPluginSetup.PreparedSetupData memory _preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        GovernanceWrappedERC20 _wrappedToken = GovernanceWrappedERC20(_preparedSetupData.helpers[0]);
        assertEq(_wrappedToken.name(), "My Token");
        assertEq(_wrappedToken.symbol(), "MTK");

        assertEq(_wrappedToken.balanceOf(address(0x1234)), 100);
        assertEq(_wrappedToken.balanceOf(address(0x5678)), 200);
        assertEq(_wrappedToken.balanceOf(address(0x0)), 0);
    }

    // HELPERS
    function createProxyAndCall(address _logic, bytes memory _data) private returns (address) {
        return address(new ERC1967Proxy(_logic, _data));
    }
}
