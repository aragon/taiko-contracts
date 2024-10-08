// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {IOptimisticTokenVoting} from "./interfaces/IOptimisticTokenVoting.sol";

import {ProposalUpgradeable} from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {RATIO_BASE, _applyRatioCeiled, RatioOutOfBounds} from "@aragon/osx/plugins/utils/Ratio.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {ITaikoL1} from "./adapted-dependencies/ITaikoL1.sol";

/// @title OptimisticTokenVotingPlugin
/// @author Aragon Association - 2023-2024
/// @notice The abstract implementation of optimistic majority plugins.
///
/// @dev This contract implements the `IOptimisticTokenVoting` interface.
contract OptimisticTokenVotingPlugin is
    IOptimisticTokenVoting,
    IMembership,
    Initializable,
    ERC165Upgradeable,
    PluginUUPSUpgradeable,
    ProposalUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /// @notice A container for the optimistic majority settings that will be applied as parameters on proposal creation.
    /// @param minVetoRatio The support threshold value. Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    /// @param l2InactivityPeriod The age in seconds of the latest block, after which the L2 is considered unavailable.
    /// @param l2AggregationGracePeriod The amount of extra seconds to allow for L2 veto bridging after `vetoEndDate` is reached.
    /// @param skipL2 Defines wether the plugin should ignore the voting power bridged to the L2, in terms of the token supply and L2 votes accepted. NOTE: Ongoing proposals will keep the value of the setting at the time of creation.
    struct OptimisticGovernanceSettings {
        uint32 minVetoRatio;
        uint64 minDuration;
        uint64 l2InactivityPeriod;
        uint64 l2AggregationGracePeriod;
        bool skipL2;
    }

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param parameters The proposal parameters at the time of the proposal creation.
    /// @param vetoTally The amount of voting power used to veto the proposal.
    /// @param vetoVoters The voters who have vetoed.
    /// @param metadataURI The IPFS URI where the proposal metadata is pinned.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    /// @param aggregatedL2Balance The amount of balance that has been registered from the L2.
    struct Proposal {
        bool executed;
        ProposalParameters parameters;
        uint256 vetoTally;
        mapping(address => bool) vetoVoters;
        bytes metadataURI;
        IDAO.Action[] actions;
        uint256 allowFailureMap;
        uint256 aggregatedL2Balance;
    }

    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param vetoEndDate The end date of the proposal vote.
    /// @param snapshotTimestamp The timestamp prior to the proposal creation.
    /// @param minVetoRatio The minimum veto ratio needed to defeat the proposal, as a fraction of 1_000_000.
    /// @param unavailableL2 True if the L2 was unavailable when the proposal was created.
    struct ProposalParameters {
        uint64 vetoEndDate;
        uint64 snapshotTimestamp;
        uint32 minVetoRatio;
        bool unavailableL2;
    }

    /// @notice The ID of the permission required to create a proposal.
    bytes32 public constant PROPOSER_PERMISSION_ID = keccak256("PROPOSER_PERMISSION");

    /// @notice The ID of the permission required to call the `updateOptimisticGovernanceSettings` function.
    bytes32 public constant UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION");

    /// @notice An [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes) compatible contract referencing the token being used for voting.
    IVotesUpgradeable public votingToken;

    /// @notice The address of the L2 token bridge, to determine the L2 balance bridged to the L2 on proposal creation.
    address public taikoBridge;

    /// @notice Taiko L1 contract to check the status from.
    ITaikoL1 public taikoL1;

    /// @notice The struct storing the governance settings.
    /// @dev Takes 1 storage slot (32+64+64+64)
    OptimisticGovernanceSettings public governanceSettings;

    /// @notice A mapping between proposal IDs and proposal information.
    mapping(uint256 => Proposal) internal proposals;

    /// @notice A mapping to enumerate proposal ID's by index
    mapping(uint256 => uint256) public proposalIds;

    /// @notice Emitted when the vetoing settings are updated.
    /// @param minVetoRatio The minimum veto ratio needed to defeat the proposal, as a fraction of 1_000_000.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    /// @param l2InactivityPeriod The age in seconds of the latest block, after which the L2 is considered unavailable.
    /// @param l2AggregationGracePeriod The amount of extra seconds to allow for L2 veto bridging after `vetoEndDate` is reached.
    /// @param skipL2 Defines wether the plugin should ignore the voting power bridged to the L2, in terms of the token supply and L2 votes accepted.
    event OptimisticGovernanceSettingsUpdated(
        uint32 minVetoRatio, uint64 minDuration, uint64 l2AggregationGracePeriod, uint64 l2InactivityPeriod, bool skipL2
    );

    /// @notice Emitted when a veto is cast by a voter.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter casting the veto.
    /// @param votingPower The voting power behind this veto.
    event VetoCast(uint256 indexed proposalId, address indexed voter, uint256 votingPower);

    /// @notice Thrown if a date is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error DurationOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown if the minimum duration value is out of bounds (less than four days or greater than 1 year).
    /// @param limit The limit value.
    /// @param actual The actual value.
    error MinDurationOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown when a sender is not allowed to create a proposal.
    /// @param sender The sender address.
    error ProposalCreationForbidden(address sender);

    /// @notice Thrown if an account is not allowed to cast a veto. This can be because the challenge period
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the account doesn't have vetoing powers.
    /// @param proposalId The ID of the proposal.
    /// @param account The address of the _account.
    error ProposalVetoingForbidden(uint256 proposalId, address account);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);

    /// @notice Thrown if the voting power is zero
    error NoVotingPower();

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _governanceSettings The vetoing settings.
    /// @param _token The [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token used for voting.
    /// @param _taikoL1 The address of the contract where the protocol status can be checked.
    /// @param _taikoBridge The address of the contract that can bridge voting vetoes back.
    function initialize(
        IDAO _dao,
        OptimisticGovernanceSettings calldata _governanceSettings,
        IVotesUpgradeable _token,
        address _taikoL1,
        address _taikoBridge
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);

        if (_taikoL1 == address(0)) revert();

        votingToken = _token;
        taikoL1 = ITaikoL1(_taikoL1);
        taikoBridge = _taikoBridge;

        _updateOptimisticGovernanceSettings(_governanceSettings);
        emit MembershipContractAnnounced({definingContract: address(_token)});
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, PluginUUPSUpgradeable, ProposalUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc IOptimisticTokenVoting
    function totalVotingPower(uint256 _timestamp) public view returns (uint256) {
        return votingToken.getPastTotalSupply(_timestamp);
    }

    /// @inheritdoc IOptimisticTokenVoting
    function bridgedVotingPower(uint256 _timestamp) public view returns (uint256) {
        return votingToken.getPastVotes(taikoBridge, _timestamp);
    }

    /// @inheritdoc IOptimisticTokenVoting
    function effectiveVotingPower(uint256 _timestamp, bool _includeL2VotingPower) public view returns (uint256) {
        uint256 _totalVotingPower = totalVotingPower(_timestamp);
        if (!_includeL2VotingPower) {
            return _totalVotingPower - bridgedVotingPower(_timestamp);
        }
        return _totalVotingPower;
    }

    /// @notice Determines whether L2 votes are currently usable for voting
    function isL2Available() public view returns (bool) {
        // Actively disabled L2 voting?
        if (governanceSettings.skipL2) return false;

        // Is the L1 bridge paused?
        try taikoL1.paused() returns (bool paused) {
            if (paused) return false;
        } catch {
            // Assume that L2 is not available if we can't read properly
            return false;
        }

        try taikoL1.getLastVerifiedBlock() returns (uint64, bytes32, bytes32, uint64 verifiedAt) {
            // verifiedAt < (block.timestamp - l2InactivityPeriod), written as a sum
            if ((verifiedAt + governanceSettings.l2InactivityPeriod) < block.timestamp) return false;
        } catch {
            // Assume that L2 is not available if we can't read properly
            return false;
        }
        return true;
    }

    /// @inheritdoc IOptimisticTokenVoting
    function minVetoRatio() public view virtual returns (uint32) {
        return governanceSettings.minVetoRatio;
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        // A member must own at least one token or have at least one token delegated to her/him.
        return votingToken.getVotes(_account) > 0 || IERC20Upgradeable(address(votingToken)).balanceOf(_account) > 0;
    }

    /// @inheritdoc IOptimisticTokenVoting
    function hasVetoed(uint256 _proposalId, address _voter) public view returns (bool) {
        return proposals[_proposalId].vetoVoters[_voter];
    }

    /// @inheritdoc IOptimisticTokenVoting
    function canVeto(uint256 _proposalId, address _voter) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }

        // The voter already vetoed.
        if (proposal_.vetoVoters[_voter]) {
            return false;
        }

        // The voter has no voting power.
        if (votingToken.getPastVotes(_voter, proposal_.parameters.snapshotTimestamp) == 0) {
            return false;
        }

        // The bridge cannot vote directly. It must use a dedicated function.
        if (_voter == taikoBridge) {
            return false;
        }

        return true;
    }

    /// @inheritdoc IOptimisticTokenVoting
    function canExecute(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // Verify that the vote has not been executed already.
        if (proposal_.executed) {
            return false;
        }
        // Check that the proposal vetoing time frame already expired
        else if (!_isProposalEnded(proposal_)) {
            return false;
        }
        // Check if L2 bridged vetoes are still possible
        // For emergency multisig proposals with _duration == 0, this will return false because the L2 aggregation is skipped
        else if (_proposalL2VetoAggregationOpen(proposal_)) {
            return false;
        }
        // Check that not enough voters have vetoed the proposal
        else if (isMinVetoRatioReached(_proposalId)) {
            return false;
        }

        return true;
    }

    /// @inheritdoc IOptimisticTokenVoting
    function isMinVetoRatioReached(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        bool _usingL2VotingPower = _proposalUsesL2Vetoes(proposal_);
        uint256 _totalVotingPower = effectiveVotingPower(proposal_.parameters.snapshotTimestamp, _usingL2VotingPower);
        uint256 _minVetoPower = _applyRatioCeiled(_totalVotingPower, proposal_.parameters.minVetoRatio);
        return proposal_.vetoTally >= _minVetoPower;
    }

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal vote.
    /// @return vetoTally The current voting power used to veto the proposal.
    /// @return metadataURI The IPFS URI at which the metadata is pinned.
    /// @return actions The actions to be executed in the associated DAO after the proposal has passed.
    /// @return allowFailureMap The bit map representations of which actions are allowed to revert so tx still succeeds.
    function getProposal(uint256 _proposalId)
        public
        view
        virtual
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
        Proposal storage proposal_ = proposals[_proposalId];

        open = _isProposalOpen(proposal_);
        executed = proposal_.executed;
        parameters = proposal_.parameters;
        vetoTally = proposal_.vetoTally;
        metadataURI = proposal_.metadataURI;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
    }

    /// @inheritdoc IOptimisticTokenVoting
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _duration
    ) external auth(PROPOSER_PERMISSION_ID) returns (uint256 proposalId) {
        uint256 snapshotTimestamp;
        unchecked {
            snapshotTimestamp = block.timestamp - 1; // The snapshot timestamp must in the past to protect the transaction against backrunning transactions causing census changes.
        }

        // Checks
        bool _enableL2 = isL2Available() && votingToken.getPastVotes(taikoBridge, snapshotTimestamp) > 0;
        if (effectiveVotingPower(snapshotTimestamp, _enableL2) == 0) {
            revert NoVotingPower();
        }

        if (_duration < governanceSettings.minDuration) {
            revert DurationOutOfBounds({limit: governanceSettings.minDuration, actual: _duration});
        }
        uint64 _now = block.timestamp.toUint64();
        uint64 _vetoEndDate = _now + _duration; // Since `minDuration` will be less than 1 year, `startDate + minDuration` can only overflow if the `startDate` is after `type(uint64).max - minDuration`. In this case, the proposal creation will revert and another date can be picked.

        proposalId = _createProposal({
            _creator: _msgSender(),
            _metadata: _metadata,
            _startDate: _now,
            _endDate: _vetoEndDate,
            _actions: _actions,
            _allowFailureMap: _allowFailureMap
        });
        // Index the ID to make it enumerable. Proposal ID's contain timestamps and cannot be iterated
        proposalIds[proposalCount() - 1] = proposalId;

        // Store proposal related information
        Proposal storage proposal_ = proposals[proposalId];

        proposal_.metadataURI = _metadata;
        proposal_.parameters.vetoEndDate = _vetoEndDate;
        proposal_.parameters.snapshotTimestamp = snapshotTimestamp.toUint64();
        proposal_.parameters.minVetoRatio = minVetoRatio();

        // We skip the L2 bridging grace period if the L2 was down on creation or if
        // an emergency multisig proposal is passed (_duration == 0)
        if (!_enableL2 || _duration == 0) {
            proposal_.parameters.unavailableL2 = true;
        }
        if (_allowFailureMap != 0) {
            proposal_.allowFailureMap = _allowFailureMap;
        }

        for (uint256 i; i < _actions.length;) {
            proposal_.actions.push(_actions[i]);
            unchecked {
                ++i;
            }
        }

        // For emergency multisig: execute if already possible
        if (canExecute(proposalId)) {
            execute(proposalId);
        }
    }

    /// @inheritdoc IOptimisticTokenVoting
    function veto(uint256 _proposalId) public virtual {
        address _voter = _msgSender();

        if (!canVeto(_proposalId, _voter)) {
            revert ProposalVetoingForbidden({proposalId: _proposalId, account: _voter});
        }

        Proposal storage proposal_ = proposals[_proposalId];

        // This could re-enter, though we can assume the governance token is not malicious
        uint256 votingPower = votingToken.getPastVotes(_voter, proposal_.parameters.snapshotTimestamp);

        // Not checking if the voter already voted, since canVeto() did it above

        // Write the updated tally.
        proposal_.vetoTally += votingPower;
        proposal_.vetoVoters[_voter] = true;

        emit VetoCast({proposalId: _proposalId, voter: _voter, votingPower: votingPower});
    }

    /// @inheritdoc IOptimisticTokenVoting
    function execute(uint256 _proposalId) public virtual {
        if (!canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }

        proposals[_proposalId].executed = true;

        _executeProposal(dao(), _proposalId, proposals[_proposalId].actions, proposals[_proposalId].allowFailureMap);
    }

    /// @notice Updates the governance settings.
    /// @param _governanceSettings The new governance settings.
    function updateOptimisticGovernanceSettings(OptimisticGovernanceSettings calldata _governanceSettings)
        public
        virtual
        auth(UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID)
    {
        _updateOptimisticGovernanceSettings(_governanceSettings);
    }

    /// @notice Splits the components behind the given proposal ID
    /// @param _proposalId The ID to split
    function parseProposalId(uint256 _proposalId)
        public
        pure
        returns (uint256 counter, uint64 startDate, uint64 endDate)
    {
        counter = _proposalId & type(uint64).max;
        startDate = uint64(_proposalId >> 128) & type(uint64).max;
        endDate = uint64(_proposalId >> 64) & type(uint64).max;
    }

    /// @dev Creates a new proposal ID, containing the start and end timestamps
    function _makeProposalId(uint64 _startDate, uint64 _endDate) internal returns (uint256 proposalId) {
        proposalId = uint256(_startDate) << 128 | uint256(_endDate) << 64;
        proposalId |= _createProposalId();
    }

    /// @notice Internal function to create a proposal.
    /// @param _metadata The proposal metadata.
    /// @param _startDate The start date of the proposal in seconds.
    /// @param _endDate The end date of the proposal in seconds.
    /// @param _allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @return proposalId The ID of the proposal.
    function _createProposal(
        address _creator,
        bytes calldata _metadata,
        uint64 _startDate,
        uint64 _endDate,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap
    ) internal override returns (uint256 proposalId) {
        // Returns an autoincremental number with the start and end dates
        proposalId = _makeProposalId(_startDate, _endDate);

        emit ProposalCreated({
            proposalId: proposalId,
            creator: _creator,
            metadata: _metadata,
            startDate: _startDate,
            endDate: _endDate,
            actions: _actions,
            allowFailureMap: _allowFailureMap
        });
    }

    /// @notice Internal implementation
    function _updateOptimisticGovernanceSettings(OptimisticGovernanceSettings calldata _governanceSettings) internal {
        // Require the minimum veto ratio value to be in the interval [0, 10^6], because `>=` comparision is used.
        if (_governanceSettings.minVetoRatio == 0) {
            revert RatioOutOfBounds({limit: 1, actual: _governanceSettings.minVetoRatio});
        } else if (_governanceSettings.minVetoRatio > RATIO_BASE) {
            revert RatioOutOfBounds({limit: RATIO_BASE, actual: _governanceSettings.minVetoRatio});
        }

        // MinDuration is not constrained on the lower side, since the emergency plugin needs to submit
        // direct proposals after a super majority has approved them.

        // StandardProposalCondition.sol ensures that all proposals created via the standard Multisig have
        // the expected minimum duration.

        if (_governanceSettings.minDuration > 365 days) {
            revert MinDurationOutOfBounds({limit: 365 days, actual: _governanceSettings.minDuration});
        }

        governanceSettings = _governanceSettings;

        emit OptimisticGovernanceSettingsUpdated({
            minVetoRatio: _governanceSettings.minVetoRatio,
            minDuration: _governanceSettings.minDuration,
            l2AggregationGracePeriod: _governanceSettings.l2AggregationGracePeriod,
            l2InactivityPeriod: _governanceSettings.l2InactivityPeriod,
            skipL2: _governanceSettings.skipL2
        });
    }

    /// @notice Internal function to check if a proposal vote is open.
    /// @param proposal_ The proposal struct.
    /// @return True if the proposal vote is open, false otherwise.
    function _isProposalOpen(Proposal storage proposal_) internal view virtual returns (bool) {
        return block.timestamp.toUint64() < proposal_.parameters.vetoEndDate && !proposal_.executed;
    }

    /// @notice Internal function to check if a proposal already ended.
    /// @param proposal_ The proposal struct.
    /// @return True if the end date of the proposal is already in the past, false otherwise.
    function _isProposalEnded(Proposal storage proposal_) internal view virtual returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return currentTime >= proposal_.parameters.vetoEndDate;
    }

    /// @notice Determines whether the proposal has L2 voting enabled or not.
    /// @param proposal_ The proposal
    function _proposalUsesL2Vetoes(Proposal storage proposal_) internal view returns (bool) {
        if (_proposalL2VetoAggregationOpen(proposal_)) {
            return true;
        }

        // No more L2 vetoes can be registered
        // return false if no L2 votes have been aggregated until now
        return proposal_.aggregatedL2Balance > 0;
    }

    /// @notice Internal function to check if a proposal may still receive L2 vetoes.
    /// @param proposal_ The proposal struct.
    /// @return True if the proposal may still receive L2 bridged votes, false otherwise.
    function _proposalL2VetoAggregationOpen(Proposal storage proposal_) internal view virtual returns (bool) {
        if (proposal_.parameters.unavailableL2) {
            return false;
        }

        return
            block.timestamp.toUint64() < proposal_.parameters.vetoEndDate + governanceSettings.l2AggregationGracePeriod;
    }

    /// @notice This empty reserved space is put in place to allow future versions to add new variables without shifting down storage in the inheritance chain (see [OpenZeppelin's guide about storage gaps](https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[44] private __gap;
}
