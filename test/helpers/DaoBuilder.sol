// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../../src/Multisig.sol";
import {EmergencyMultisig} from "../../src/EmergencyMultisig.sol";
import {OptimisticTokenVotingPlugin} from "../../src/OptimisticTokenVotingPlugin.sol";
import {createProxyAndCall} from "../../src/helpers/proxy.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";
import {TaikoL1Mock, TaikoL1PausedMock, TaikoL1WithOldLastBlock, TaikoL1Incompatible} from "../mocks/TaikoL1Mock.sol";
import {ITaikoL1} from "../../src/adapted-dependencies/ITaikoL1.sol";
import {ALICE_ADDRESS, TAIKO_BRIDGE_ADDRESS} from "../constants.sol";
import {GovernanceERC20Mock} from "../mocks/GovernanceERC20Mock.sol";

contract DaoBuilder is Test {
    address immutable DAO_BASE = address(new DAO());
    address immutable MULTISIG_BASE = address(new Multisig());
    address immutable EMERGENCY_MULTISIG_BASE = address(new EmergencyMultisig());
    address immutable OPTIMISTIC_BASE = address(new OptimisticTokenVotingPlugin());

    enum TaikoL1Status {
        Standard,
        Paused,
        OutOfSync,
        Incompatible
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
    uint64 public minDuration = 4 days;
    uint64 public l2InactivityPeriod = 10 minutes;
    uint64 public l2AggregationGracePeriod = 2 days;
    bool public skipL2 = false;

    bool public onlyListed = true;
    uint16 public minApprovals = 1;
    uint64 public stdProposalDuration = 10 days;
    uint64 multisigProposalExpirationPeriod = 10 days;

    function withDaoOwner(address newOwner) public returns (DaoBuilder) {
        owner = newOwner;
        return this;
    }

    function withOkTaikoL1() public returns (DaoBuilder) {
        taikoL1Status = TaikoL1Status.Standard;
        return this;
    }

    function withPausedTaikoL1() public returns (DaoBuilder) {
        taikoL1Status = TaikoL1Status.Paused;
        return this;
    }

    function withOutOfSyncTaikoL1() public returns (DaoBuilder) {
        taikoL1Status = TaikoL1Status.OutOfSync;
        return this;
    }

    function withIncompatibleTaikoL1() public returns (DaoBuilder) {
        taikoL1Status = TaikoL1Status.Incompatible;
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

    function withDuration(uint32 newDuration) public returns (DaoBuilder) {
        stdProposalDuration = newDuration;
        return this;
    }

    function withExpiration(uint64 newExpirationPeriod) public returns (DaoBuilder) {
        multisigProposalExpirationPeriod = newExpirationPeriod;
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

    function withSkipL2() public returns (DaoBuilder) {
        skipL2 = true;
        return this;
    }

    function withoutSkipL2() public returns (DaoBuilder) {
        skipL2 = false;
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
            GovernanceERC20Mock votingToken,
            ITaikoL1 taikoL1
        )
    {
        // Deploy the DAO with `this` as root
        dao = DAO(
            payable(
                createProxyAndCall(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        // Deploy ERC20 token
        votingToken = new GovernanceERC20Mock(address(dao));

        if (tokenHolders.length > 0) {
            for (uint256 i = 0; i < tokenHolders.length; i++) {
                votingToken.mintAndDelegate(tokenHolders[i].tokenHolder, tokenHolders[i].amount);
            }
        } else {
            votingToken.mintAndDelegate(owner, 10 ether);
        }

        // Optimistic token voting plugin
        if (taikoL1Status == TaikoL1Status.Standard) {
            taikoL1 = new TaikoL1Mock();
        } else if (taikoL1Status == TaikoL1Status.Paused) {
            taikoL1 = new TaikoL1PausedMock();
        } else if (taikoL1Status == TaikoL1Status.OutOfSync) {
            taikoL1 = new TaikoL1WithOldLastBlock();
        } else {
            taikoL1 = ITaikoL1(address(new TaikoL1Incompatible()));
        }

        {
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory targetContractSettings =
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings({
                minVetoRatio: minVetoRatio,
                minDuration: minDuration,
                l2InactivityPeriod: l2InactivityPeriod,
                l2AggregationGracePeriod: l2AggregationGracePeriod,
                skipL2: skipL2
            });

            optimisticPlugin = OptimisticTokenVotingPlugin(
                createProxyAndCall(
                    address(OPTIMISTIC_BASE),
                    abi.encodeCall(
                        OptimisticTokenVotingPlugin.initialize,
                        (dao, targetContractSettings, votingToken, address(taikoL1), taikoBridge)
                    )
                )
            );
        }

        // Standard multisig
        {
            Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
                onlyListed: onlyListed,
                minApprovals: minApprovals,
                destinationProposalDuration: stdProposalDuration,
                proposalExpirationPeriod: multisigProposalExpirationPeriod
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
                addresslistSource: multisig,
                proposalExpirationPeriod: multisigProposalExpirationPeriod
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

        if (optimisticProposers.length > 0) {
            for (uint256 i = 0; i < optimisticProposers.length; i++) {
                dao.grant(address(optimisticPlugin), optimisticProposers[i], optimisticPlugin.PROPOSER_PERMISSION_ID());
            }
        } else {
            // Ensure that at least the owner can propose
            dao.grant(address(optimisticPlugin), owner, optimisticPlugin.PROPOSER_PERMISSION_ID());
        }

        // Revoke transfer ownership to the owner
        dao.grant(address(dao), owner, dao.ROOT_PERMISSION_ID());
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(optimisticPlugin), "OptimisticPlugin");
        vm.label(address(votingToken), "VotingToken");
        vm.label(address(multisig), "Multisig");
        vm.label(address(emergencyMultisig), "EmergencyMultisig");
        vm.label(address(taikoL1), "TaikoL1");
        vm.label(address(taikoBridge), "TaikoBridge");

        // Moving forward to avoid proposal creations failing or getVotes() giving inconsistent values
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
