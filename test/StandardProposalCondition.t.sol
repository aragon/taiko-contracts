// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {StandardProposalCondition} from "../src/conditions/StandardProposalCondition.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPermissionCondition} from "@aragon/osx/core/permission/IPermissionCondition.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";
import {RATIO_BASE, RatioOutOfBounds} from "@aragon/osx/plugins/utils/Ratio.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

uint32 constant MIN_DELAY_1 = 1000;
uint32 constant MIN_DELAY_2 = 5000;

contract StandardProposalConditionTest is Test {
    DAO dao;
    StandardProposalCondition public condition;

    function setUp() public {
        dao = DAO(payable(address(0x12345678)));
        condition = new StandardProposalCondition(address(dao), MIN_DELAY_1);
    }

    function test_ShouldRevertWithoutDao() public {
        HelperStandardProposalConditionDeploy helper = new HelperStandardProposalConditionDeploy();

        vm.expectRevert(abi.encodeWithSelector(StandardProposalCondition.EmptyDao.selector));
        helper.deployConditionWithNoDao();
    }

    function test_ShouldRevertWithoutDelay() public {
        HelperStandardProposalConditionDeploy helper = new HelperStandardProposalConditionDeploy();

        vm.expectRevert(abi.encodeWithSelector(StandardProposalCondition.EmptyDelay.selector));
        helper.deployConditionWithNoDelay();
    }

    function test_ShouldAllowWhenEnoughDelay() public view {
        // Bare minimum
        uint32 votingDuration = MIN_DELAY_1;

        // Create proposal with enough delay
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        bytes memory data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        bool granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, true, "Condition should pass");

        // More delay
        votingDuration = MIN_DELAY_1 * 10;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, true, "Condition should still pass");

        // More delay
        votingDuration = MIN_DELAY_1 * 1000;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, true, "Condition should still pass");

        // More delay
        votingDuration = MIN_DELAY_1 * 100000;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, true, "Condition should still pass");
    }

    function test_ShouldReturnFalseWhenNotEnoughDelay() public view {
        // Almost the minimum
        uint32 votingDuration = MIN_DELAY_1 - 1;

        // Create proposal with enough delay
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        bytes memory data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        bool granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        votingDuration = MIN_DELAY_1 - 2;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        votingDuration = MIN_DELAY_1 - 20;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        votingDuration = MIN_DELAY_1 / 2;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        votingDuration = MIN_DELAY_1 / 5;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        votingDuration = MIN_DELAY_1 / 50;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        votingDuration = MIN_DELAY_1 / 500;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Zero votingDuration
        votingDuration = 0;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, votingDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");
    }

    // LONGER DELAY

    function test_ShouldAllowWhenEnoughDelay2() public {
        dao = DAO(payable(address(0x12345678)));
        condition = new StandardProposalCondition(address(dao), MIN_DELAY_2);

        // Bare minimum
        uint32 voteDuration = MIN_DELAY_2;

        // Create proposal with enough delay
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        bytes memory data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        bool granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, true, "Condition should pass");

        // More delay
        voteDuration = MIN_DELAY_2 * 10;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, true, "Condition should still pass");

        // More delay
        voteDuration = MIN_DELAY_2 * 1000;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, true, "Condition should still pass");

        // More delay
        voteDuration = MIN_DELAY_2 * 100000;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, true, "Condition should still pass");
    }

    function test_ShouldReturnFalseWhenNotEnoughDelay2() public {
        dao = DAO(payable(address(0x12345678)));
        condition = new StandardProposalCondition(address(dao), MIN_DELAY_2);

        // Almost the minimum
        uint32 voteDuration = MIN_DELAY_2 - 1;

        // Create proposal with enough delay
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        bytes memory data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        bool granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        voteDuration = MIN_DELAY_2 - 2;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        voteDuration = MIN_DELAY_2 - 20;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        voteDuration = MIN_DELAY_2 / 2;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        voteDuration = MIN_DELAY_2 / 5;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        voteDuration = MIN_DELAY_2 / 50;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Less delay
        voteDuration = MIN_DELAY_2 / 500;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");

        // Zero voteDuration
        voteDuration = 0;

        data = abi.encodeCall(OptimisticTokenVotingPlugin.createProposal, ("", actions, 0, voteDuration));
        granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");
    }

    function testFuzz_ShouldReturnFalseWhenInvalidSelector(bytes4 selector) public {
        dao = DAO(payable(address(0x12345678)));
        condition = new StandardProposalCondition(address(dao), MIN_DELAY_2);

        IDAO.Action[] memory actions = new IDAO.Action[](1);

        if (selector == OptimisticTokenVotingPlugin.createProposal.selector) {
            bytes memory _data = abi.encodeWithSelector(selector, "", actions, 0, MIN_DELAY_2);
            bool _granted = condition.isGranted(address(0x0), address(0x0), 0, _data);
            assertEq(_granted, true, "Condition should pass");
            return;
        }

        bytes memory data = abi.encodeWithSelector(selector, "", actions, 0, MIN_DELAY_2);
        bool granted = condition.isGranted(address(0x0), address(0x0), 0, data);
        assertEq(granted, false, "Condition should not pass");
    }

    function testFuzz_SupportsTheRightInterfaces(bytes4 interfaceId) public view {
        if (interfaceId == type(IPermissionCondition).interfaceId || interfaceId == type(IERC165).interfaceId) {
            // Should be true
            assertEq(condition.supportsInterface(interfaceId), true, "Should support it");
            return;
        }

        // Should be false
        assertEq(condition.supportsInterface(interfaceId), false, "Should not support it");
    }
}

contract HelperStandardProposalConditionDeploy {
    function deployConditionWithNoDao() public {
        new StandardProposalCondition(address(0), MIN_DELAY_1);
    }

    function deployConditionWithNoDelay() public {
        new StandardProposalCondition(address(1234), 0);
    }
}
