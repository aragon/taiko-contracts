// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {IOptimisticTokenVoting} from "../../src/interfaces/IOptimisticTokenVoting.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

/// @notice Mock voting plugin for testing L2VetoReceiver
contract OptimisticTokenVotingPluginMock is IOptimisticTokenVoting {
    mapping(uint256 => ProposalParameters) public proposalParams;
    mapping(uint256 => uint256) public l2VetoTallies;

    uint256 public lastReceivedProposalId;
    uint256 public lastReceivedVetoTally;

    /// @notice Set up a mock proposal for testing
    function setProposal(uint256 _proposalId, uint64 _vetoStartDate, uint64 _vetoEndDate, uint64 _snapshotTimestamp)
        external
    {
        proposalParams[_proposalId] = ProposalParameters({
            vetoEndDate: _vetoEndDate,
            snapshotTimestamp: _snapshotTimestamp,
            minVetoRatio: 100000, // 10%
            unavailableL2: false,
            vetoStartDate: _vetoStartDate
        });
    }

    /// @notice Parse proposal ID to extract encoded values
    function parseProposalId(uint256 _proposalId)
        external
        pure
        returns (uint64 counter, uint64 startDate, uint64 endDate, uint64 snapshotTimestamp)
    {
        counter = uint64(_proposalId & type(uint64).max);
        endDate = uint64(_proposalId >> 64) & type(uint64).max;
        startDate = uint64(_proposalId >> 128) & type(uint64).max;
        snapshotTimestamp = uint64(_proposalId >> 192);
    }

    /// @notice Create a proposalId with encoded timestamps
    function makeProposalId(uint64 _counter, uint64 _startDate, uint64 _endDate, uint64 _snapshotTimestamp)
        external
        pure
        returns (uint256)
    {
        return uint256(_snapshotTimestamp) << 192 | uint256(_startDate) << 128 | uint256(_endDate) << 64
            | uint256(_counter);
    }

    // =========================================================================
    // IOptimisticTokenVoting Implementation
    // =========================================================================

    function receiveL2Vetoes(uint256 _proposalId, uint256 _vetoTally) external override {
        lastReceivedProposalId = _proposalId;
        lastReceivedVetoTally = _vetoTally;
        l2VetoTallies[_proposalId] = _vetoTally;
    }

    function getProposal(uint256 _proposalId)
        external
        view
        override
        returns (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            uint256 vetoTally,
            bytes memory metadataURI,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        )
    {
        parameters = proposalParams[_proposalId];
        open = true;
        executed = false;
        vetoTally = l2VetoTallies[_proposalId];
        metadataURI = "";
        actions = new IDAO.Action[](0);
        allowFailureMap = 0;
    }

    // Stubs for other interface functions
    function votingToken() external pure override returns (IVotesUpgradeable) {
        return IVotesUpgradeable(address(0));
    }

    function totalVotingPower(uint256) external pure override returns (uint256) {
        return 0;
    }

    function bridgedVotingPower(uint256) external pure override returns (uint256) {
        return 0;
    }

    function effectiveVotingPower(uint256, bool) external pure override returns (uint256) {
        return 0;
    }

    function isL2Available() external pure override returns (bool) {
        return true;
    }

    function minVetoRatio() external pure override returns (uint32) {
        return 100000;
    }

    function createProposal(bytes calldata, IDAO.Action[] calldata, uint256, uint64)
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function canVeto(uint256, address) external pure override returns (bool) {
        return false;
    }
    function veto(uint256) external override {}

    function hasVetoed(uint256, address) external pure override returns (bool) {
        return false;
    }

    function isMinVetoRatioReached(uint256) external pure override returns (bool) {
        return false;
    }

    function canExecute(uint256) external pure override returns (bool) {
        return false;
    }
    function execute(uint256) external override {}
}
