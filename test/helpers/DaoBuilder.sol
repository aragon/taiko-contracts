// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../../src/Multisig.sol";
import {EmergencyMultisig} from "../../src/EmergencyMultisig.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {ERC20VotesMock} from "../mocks/ERC20VotesMock.sol";
import {createProxyAndCall} from "./proxy.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {TaikoL1Mock, TaikoL1PausedMock, TaikoL1WithOldLastBlock} from "../mocks/TaikoL1Mock.sol";
import {TaikoL1} from "../../src/adapted-dependencies/TaikoL1.sol";
import {ALICE_ADDRESS, TAIKO_BRIDGE_ADDRESS} from "../constants.sol";

contract DaoBuilder is Test {
    address immutable DAO_BASE = address(new DAO());
    address immutable MULTISIG_BASE = address(new Multisig());
    address immutable EMERGENCY_MULTISIG_BASE = address(new EmergencyMultisig());
    address immutable OPTIMISTIC_BASE = address(new OptimisticTokenVotingPlugin());
    address immutable VOTING_TOKEN_BASE = address(new ERC20VotesMock());

    enum TaikoL1Status {
        Standard,
        Paused,
        OutOfSync
    }

    struct MintEntry {
        address tokenHolder;
        uint256 amount;
    }

    address public owner = ALICE_ADDRESS;
    address public taikoBridge = TAIKO_BRIDGE_ADDRESS;

    TaikoL1Status public taikoL1Status = TaikoL1Status.Standard;
    address[] public multisigMembers;
    address[] public optimisticProposers;
    MintEntry[] public tokenHolders;

    uint32 public minVetoRatio = uint32(RATIO_BASE / 10); // 10%
    uint64 public minDuration = 0;
    uint64 public l2InactivityPeriod = 10 minutes;
    uint64 public l2AggregationGracePeriod = 2 days;

    bool public onlyListed = true;
    uint16 public minApprovals = 1;
    uint64 public stdProposalDuration = 10 days;

    function withDaoOwner(address newOwner) public returns (DaoBuilder) {
        owner = newOwner;
        return this;
    }

    function withTaikoL1Status(TaikoL1Status newStatus) public returns (DaoBuilder) {
        taikoL1Status = newStatus;
        return this;
    }

    function withTokenHolder(address newTokenHolder, uint256 amount) public returns (DaoBuilder) {
        tokenHolders.push(MintEntry({tokenHolder: newTokenHolder, amount: amount}));
        return this;
    }

    function withMinVetoRatio(uint32 newMinVetoRatio) public returns (DaoBuilder) {
        if (newMinVetoRatio > RATIO_BASE) revert("Veto rate above 100%");
        minVetoRatio = newMinVetoRatio;
        return this;
    }

    function withMinDuration(uint32 newMinDuration) public returns (DaoBuilder) {
        minDuration = newMinDuration;
        return this;
    }

    function withL2InactivityPeriod(uint64 newL2InactivityPeriod) public returns (DaoBuilder) {
        l2InactivityPeriod = newL2InactivityPeriod;
        return this;
    }

    function withL2AggregationGracePeriod(uint64 newL2AggregationGracePeriod) public returns (DaoBuilder) {
        l2AggregationGracePeriod = newL2AggregationGracePeriod;
        return this;
    }

    function withTaikoBridge(address newTaikoBridge) public returns (DaoBuilder) {
        taikoBridge = newTaikoBridge;
        return this;
    }

    function withOnlyListed() public returns (DaoBuilder) {
        onlyListed = true;
        return this;
    }

    function withoutOnlyListed() public returns (DaoBuilder) {
        onlyListed = false;
        return this;
    }

    function withMultisigMember(address newMember) public returns (DaoBuilder) {
        multisigMembers.push(newMember);
        return this;
    }

    function withProposerOnOptimistic(address newProposer) public returns (DaoBuilder) {
        optimisticProposers.push(newProposer);
        return this;
    }

    function withMinApprovals(uint16 newMinApprovals) public returns (DaoBuilder) {
        if (newMinApprovals > multisigMembers.length) revert("You should add enough multisig members first");
        minApprovals = newMinApprovals;
        return this;
    }

    /// @dev Creates a DAO with the given orchestration settings.
    /// @dev The setup is done on block/timestamp 0 and tests should be made on block/timestamp 1 or later.
    function build()
        public
        returns (
            DAO dao,
            OptimisticTokenVotingPlugin optimisticPlugin,
            Multisig multisig,
            EmergencyMultisig emergencyMultisig,
            ERC20VotesMock votingToken,
            TaikoL1 taikoL1
        )
    {
        setBlock(0);
        setTime(0);
        switchTo(owner);

        // Deploy the DAO with the owner as root
        dao = DAO(
            payable(
                createProxyAndCall(address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", owner, address(0x0), "")))
            )
        );

        // Deploy ERC20 token
        votingToken = ERC20VotesMock(
            createProxyAndCall(address(VOTING_TOKEN_BASE), abi.encodeCall(ERC20VotesMock.initialize, ()))
        );

        if (tokenHolders.length > 0) {
            for (uint256 i = 0; i < tokenHolders.length; i++) {
                undoSwitch();
                switchTo(tokenHolders[i].tokenHolder);
                votingToken.mint(tokenHolders[i].tokenHolder, tokenHolders[i].amount);
                votingToken.delegate(tokenHolders[i].tokenHolder);
            }
            undoSwitch();
            switchTo(owner);
        } else {
            votingToken.mint(owner, 10 ether);
            votingToken.delegate(owner);
        }

        // Optimistic token voting plugin
        if (taikoL1Status == TaikoL1Status.Standard) {
            taikoL1 = new TaikoL1Mock();
        } else if (taikoL1Status == TaikoL1Status.Paused) {
            taikoL1 = new TaikoL1PausedMock();
        } else {
            taikoL1 = new TaikoL1WithOldLastBlock();
        }

        {
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory targetContractSettings =
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
                minVetoRatio: minVetoRatio,
                minDuration: minDuration,
                l2InactivityPeriod: l2InactivityPeriod,
                l2AggregationGracePeriod: l2AggregationGracePeriod
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

        // Standard multisig
        {
            Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
                onlyListed: onlyListed,
                minApprovals: minApprovals,
                destinationProposalDuration: stdProposalDuration
            });

            address[] memory signers;
            if (multisigMembers.length > 0) {
                signers = multisigMembers;
            } else {
                // Ensure 1 member by default
                signers = new address[](1);
                signers[0] = owner;
            }
            multisig = Multisig(
                createProxyAndCall(
                    address(MULTISIG_BASE), abi.encodeCall(Multisig.initialize, (dao, signers, settings))
                )
            );
        }

        // Emergency Multisig
        {
            EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig.MultisigSettings({
                onlyListed: onlyListed,
                minApprovals: minApprovals,
                addresslistSource: multisig
            });

            emergencyMultisig = EmergencyMultisig(
                createProxyAndCall(
                    address(EMERGENCY_MULTISIG_BASE), abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
                )
            );
        }

        // Optimistic can execute on the DAO
        dao.grant(address(dao), address(optimisticPlugin), dao.EXECUTE_PERMISSION_ID());

        // Multisig can create proposals on the optimistic plugin
        dao.grant(address(optimisticPlugin), address(multisig), optimisticPlugin.PROPOSER_PERMISSION_ID());

        // Emergency Multisig can create proposals on the optimistic plugin
        dao.grant(address(optimisticPlugin), address(emergencyMultisig), optimisticPlugin.PROPOSER_PERMISSION_ID());

        // Moving forward to avoid proposal creations failing or getVotes() giving inconsistent values
        blockForward(1);
        timeForward(1);

        undoSwitch();
    }

    // Helpers

    /// @notice Tells Foundry to continue executing from the given wallet.
    function switchTo(address target) internal {
        vm.startPrank(target);
    }

    /// @notice Tells Foundry to stop using the last labeled wallet.
    function undoSwitch() internal {
        vm.stopPrank();
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
