// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {NonblockingLzApp} from "./lzApp/NonblockingLzApp.sol";

/// @title OptimisticTokenVotingPlugin
/// @author Aragon Association - 2023
/// @notice The abstract implementation of optimistic majority plugins.
///
/// @dev This contract implements the `IOptimisticTokenVoting` interface.
contract L2VetoAggregation is NonblockingLzApp {
    struct Proposal {
        uint256 startDate;
        uint256 endDate;
    }

    /// @notice A container for the majority voting bridge settings that will be required when bridging and receiving the proposals from other chains
    /// @param chainID A parameter to select the id of the destination chain
    /// @param bridge A parameter to select the address of the bridge you want to interact with
    /// @param l2vVotingAggregator A parameter to select the address of the voting contract that will live in the L2
    struct BridgeSettings {
        uint16 chainId;
        address bridge;
        address l1Plugin;
    }

    IVotesUpgradeable immutable votingToken;
    BridgeSettings bridgeSettings;

    /// @notice A mapping for the live proposals
    mapping(uint256 => Proposal) internal liveProposals;

    /// @notice A mapping for the live proposals
    mapping(uint256 => uint256) internal proposalVetoes;

    /// @notice A mapping for the addresses that have voted
    mapping(address => bool) internal voted;

    /// @notice A mapping for the addresses that have voted
    mapping(uint256 => bool) internal proposalBridged;

    error ProposalEnded();
    error UserAlreadyVoted();
    error ProposalAlreadyBridged();
    error BridgeAlreadySet();

    constructor(IVotesUpgradeable _votingToken) {
        votingToken = _votingToken;
    }

    function initialize(BridgeSettings memory _bridgeSettings) public {
        if (bridgeSettings.chainId != 0) {
            revert BridgeAlreadySet();
        }
        bridgeSettings = _bridgeSettings;
        __LzApp_init(bridgeSettings.bridge);

        bytes memory remoteAndLocalAddresses = abi.encodePacked(
            _bridgeSettings.l1Plugin,
            address(this)
        );
        setTrustedRemoteAddress(
            _bridgeSettings.chainId,
            remoteAndLocalAddresses
        );
    }

    // This function is called when data is received. It overrides the equivalent function in the parent contract.
    // This function should only be called from the L2 to send the aggregated votes and nothing else
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        // The LayerZero _payload (message) is decoded as a string and stored in the "data" variable.
        require(
            _msgSender() == address(this),
            "NonblockingLzApp: caller must be LzApp"
        );
        (uint256 proposalId, uint256 startDate, uint256 endDate) = abi.decode(
            _payload,
            (uint256, uint256, uint256)
        );

        liveProposals[proposalId] = Proposal(startDate, endDate);
    }

    function vote(uint256 _proposalId) external {
        address _voter = _msgSender();

        Proposal storage proposal_ = liveProposals[_proposalId];
        if (proposal_.endDate > block.timestamp) {
            revert ProposalEnded();
        }

        if (voted[_voter] == true) {
            revert UserAlreadyVoted();
        }

        voted[_voter] = true;

        uint256 votingPower = votingToken.getPastVotes(
            _voter,
            proposal_.startDate
        );

        proposalVetoes[_proposalId] += votingPower;
    }

    function bridgeResults(uint256 _proposalId) external {
        if (proposalBridged[_proposalId]) {
            revert ProposalAlreadyBridged();
        }
        bytes memory encodedMessage = abi.encode(
            _proposalId,
            proposalVetoes[_proposalId]
        );

        proposalBridged[_proposalId] = true;

        _lzSend({
            _dstChainId: bridgeSettings.chainId,
            _payload: encodedMessage,
            _refundAddress: payable(msg.sender),
            _zroPaymentAddress: address(0),
            _adapterParams: bytes(""),
            _nativeFee: address(this).balance
        });
    }
}
