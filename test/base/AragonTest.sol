// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IPluginSetup, PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../../src/Multisig.sol";
import {EmergencyMultisig} from "../../src/EmergencyMultisig.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {ERC20VotesMock} from "../mocks/ERC20VotesMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {createProxyAndCall} from "../helpers.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {TaikoL1UnpausedMock} from "../mocks/TaikoL1Mock.sol";
import {TaikoL1} from "../../src/adapted-dependencies/TaikoL1.sol";

import {Test} from "forge-std/Test.sol";

contract AragonTest is Test {
    address immutable alice = address(0xa11ce);
    address immutable bob = address(0xB0B);
    address immutable carol = address(0xc4601);
    address immutable david = address(0xd471d);
    address immutable taikoBridge = address(0xb61d6e);
    address immutable randomWallet = vm.addr(1234567890);

    address immutable DAO_BASE = address(new DAO());
    address immutable MULTISIG_BASE = address(new Multisig());
    address immutable EMERGENCY_MULTISIG_BASE = address(new EmergencyMultisig());
    address immutable OPTIMISTIC_BASE = address(new OptimisticTokenVotingPlugin());
    address immutable VOTING_TOKEN_BASE = address(new ERC20VotesMock());

    bytes internal constant EMPTY_BYTES = "";

    constructor() {
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");
        vm.label(david, "David");
        vm.label(taikoBridge, "Bridge");
        vm.label(randomWallet, "Random wallet");
    }

    function makeDaoWithOptimisticTokenVoting(address owner)
        internal
        returns (DAO, OptimisticTokenVotingPlugin, ERC20VotesMock, TaikoL1)
    {
        // Deploy a DAO with owner as root
        DAO dao = DAO(
            payable(
                createProxyAndCall(address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", owner, address(0x0), "")))
            )
        );

        // Deploy ERC20 token
        ERC20VotesMock votingToken = ERC20VotesMock(
            createProxyAndCall(address(VOTING_TOKEN_BASE), abi.encodeCall(ERC20VotesMock.initialize, ()))
        );
        votingToken.mint(alice, 10 ether);
        votingToken.delegate(alice);
        blockForward(1);

        // Deploy a new plugin instance
        TaikoL1UnpausedMock taikoL1 = new TaikoL1UnpausedMock();

        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: uint32(RATIO_BASE / 10),
            minDuration: 10 days,
            l2InactivityPeriod: 10 minutes,
            l2AggregationGracePeriod: 2 days
        });

        OptimisticTokenVotingPlugin optimisticPlugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                address(OPTIMISTIC_BASE),
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize, (dao, settings, votingToken, taikoL1, taikoBridge)
                )
            )
        );

        // The plugin can execute on the DAO
        dao.grant(address(dao), address(optimisticPlugin), dao.EXECUTE_PERMISSION_ID());

        // Alice can create proposals on the plugin
        dao.grant(address(optimisticPlugin), alice, optimisticPlugin.PROPOSER_PERMISSION_ID());

        vm.label(address(dao), "dao");
        vm.label(address(optimisticPlugin), "optimisticPlugin");

        return (dao, optimisticPlugin, votingToken, TaikoL1(taikoL1));
    }

    /// @notice Creates a mock DAO with a multisig and an optimistic token voting plugin.
    /// @param owner The address that will be set as root on the DAO.
    /// @return A tuple containing the DAO and the address of the plugin.
    function makeDaoWithMultisigAndOptimistic(address owner)
        internal
        returns (DAO, Multisig, OptimisticTokenVotingPlugin)
    {
        // Deploy a DAO with owner as root
        DAO dao = DAO(
            payable(
                createProxyAndCall(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, (EMPTY_BYTES, owner, address(0x0), ""))
                )
            )
        );
        Multisig multisig;
        OptimisticTokenVotingPlugin optimisticPlugin;

        {
            // Deploy ERC20 token
            ERC20VotesMock votingToken = ERC20VotesMock(
                createProxyAndCall(address(VOTING_TOKEN_BASE), abi.encodeCall(ERC20VotesMock.initialize, ()))
            );
            votingToken.mint();

            // Deploy a target contract for passed proposals to be created in
            TaikoL1UnpausedMock taikoL1 = new TaikoL1UnpausedMock();

            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory targetContractSettings =
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
                minVetoRatio: uint32(RATIO_BASE / 10),
                minDuration: 4 days,
                l2InactivityPeriod: 10 minutes,
                l2AggregationGracePeriod: 2 days
            });

            optimisticPlugin = OptimisticTokenVotingPlugin(
                createProxyAndCall(
                    address(OPTIMISTIC_BASE),
                    abi.encodeCall(
                        OptimisticTokenVotingPlugin.initialize,
                        (dao, targetContractSettings, votingToken, taikoL1, taikoBridge)
                    )
                )
            );
        }

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings =
                Multisig.MultisigSettings({onlyListed: true, minApprovals: 3, destinationProposalDuration: 4 days});
            address[] memory signers = new address[](4);
            signers[0] = alice;
            signers[1] = bob;
            signers[2] = carol;
            signers[3] = david;

            multisig = Multisig(
                createProxyAndCall(
                    address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings))
                )
            );
        }

        vm.label(address(dao), "dao");
        vm.label(address(multisig), "multisig");
        vm.label(address(optimisticPlugin), "optimisticPlugin");

        return (dao, multisig, optimisticPlugin);
    }

    /// @notice Creates a mock DAO with an emergency multisig, a multisig with the address list and an optimistic token voting plugin.
    /// @param owner The address that will be set as root on the DAO.
    /// @return A tuple containing the DAO and the address of the plugin.
    function makeDaoWithEmergencyMultisigAndOptimistic(address owner)
        internal
        returns (DAO, EmergencyMultisig, Multisig, OptimisticTokenVotingPlugin)
    {
        // Deploy a DAO with owner as root
        DAO dao = DAO(
            payable(
                createProxyAndCall(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, (EMPTY_BYTES, owner, address(0x0), ""))
                )
            )
        );
        Multisig multisig;
        EmergencyMultisig emergencyMultisig;
        OptimisticTokenVotingPlugin optimisticPlugin;

        {
            // Deploy ERC20 token
            ERC20VotesMock votingToken = ERC20VotesMock(
                createProxyAndCall(address(VOTING_TOKEN_BASE), abi.encodeCall(ERC20VotesMock.initialize, ()))
            );
            votingToken.mint();

            // Deploy a target contract for passed proposals to be created in
            TaikoL1UnpausedMock taikoL1 = new TaikoL1UnpausedMock();

            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory targetContractSettings =
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
                minVetoRatio: uint32(RATIO_BASE / 10),
                minDuration: 0,
                l2InactivityPeriod: 10 minutes,
                l2AggregationGracePeriod: 2 days
            });

            optimisticPlugin = OptimisticTokenVotingPlugin(
                createProxyAndCall(
                    address(OPTIMISTIC_BASE),
                    abi.encodeCall(
                        OptimisticTokenVotingPlugin.initialize,
                        (dao, targetContractSettings, votingToken, taikoL1, taikoBridge)
                    )
                )
            );
        }

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings =
                Multisig.MultisigSettings({onlyListed: true, minApprovals: 3, destinationProposalDuration: 4 days});
            address[] memory signers = new address[](4);
            signers[0] = alice;
            signers[1] = bob;
            signers[2] = carol;
            signers[3] = david;

            multisig = Multisig(
                createProxyAndCall(
                    address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings))
                )
            );
        }

        {
            // Deploy a new emergency multisig instance
            EmergencyMultisig.MultisigSettings memory settings =
                EmergencyMultisig.MultisigSettings({onlyListed: true, minApprovals: 3, addresslistSource: multisig});

            emergencyMultisig = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
        }

        dao.grant(address(optimisticPlugin), address(emergencyMultisig), optimisticPlugin.PROPOSER_PERMISSION_ID());
        dao.grant(address(dao), address(optimisticPlugin), dao.EXECUTE_PERMISSION_ID());

        vm.label(address(dao), "dao");
        vm.label(address(emergencyMultisig), "emergencyMultisig");
        vm.label(address(multisig), "multisig");
        vm.label(address(optimisticPlugin), "optimisticPlugin");

        return (dao, emergencyMultisig, multisig, optimisticPlugin);
    }

    /// @notice Tells Foundry to continue executing from the given wallet.
    function switchTo(address target) internal {
        vm.startPrank(target);
    }

    /// @notice Tells Foundry to stop using the last labeled wallet.
    function undoSwitch() internal {
        vm.stopPrank();
    }

    /// @notice Returns the address and private key associated to the given label.
    /// @param label The label to get the address and private key for.
    /// @return addr The address associated with the label.
    /// @return pk The private key associated with the label.
    function getWallet(string memory label) internal returns (address addr, uint256 pk) {
        pk = uint256(keccak256(abi.encodePacked(label)));
        addr = vm.addr(pk);
        vm.label(addr, label);
    }

    /// @notice Moves the EVM time forward by a given amount.
    /// @param time The amount of seconds to advance.
    function timeForward(uint256 time) internal {
        vm.warp(block.timestamp + time);
    }

    /// @notice Moves the EVM time back by a given amount.
    /// @param time The amount of seconds to subtract.
    function timeBack(uint256 time) internal {
        vm.warp(block.timestamp - time);
    }

    /// @notice Sets the EVM timestamp.
    /// @param timestamp The timestamp in seconds.
    function setTime(uint256 timestamp) internal {
        vm.warp(timestamp);
    }

    /// @notice Moves the EVM block number forward by a given amount.
    /// @param blocks The number of blocks to advance.
    function blockForward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }

    /// @notice Moves the EVM block number back by a given amount.
    /// @param blocks The number of blocks to subtract.
    function blockBack(uint256 blocks) internal {
        vm.roll(block.number - blocks);
    }

    /// @notice Set the EVM block number to the given value.
    /// @param blockNumber The new block number
    function setBlock(uint256 blockNumber) internal {
        vm.roll(blockNumber);
    }
}
