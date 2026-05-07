// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {createProxyAndCall} from "../../../src/helpers/proxy.sol";
import {OptimisticTokenVotingPlugin} from "../../../src/OptimisticTokenVotingPlugin.sol";
import {L2VetoAggregator} from "../../../src/crosschain/L2VetoAggregator.sol";
import {L2VetoReceiver} from "../../../src/crosschain/L2VetoReceiver.sol";
import {GovernanceERC20Mock} from "../../mocks/GovernanceERC20Mock.sol";
import {TaikoL1Mock} from "../../mocks/TaikoL1Mock.sol";
import {TaikoBridgeMock} from "../../mocks/TaikoBridgeMock.sol";
import {RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";

contract InvariantTestSetup is Test {
    // =========================================================================
    // CONTRACTS
    // =========================================================================

    DAO public dao;
    OptimisticTokenVotingPlugin public plugin;
    GovernanceERC20Mock public votingToken;
    L2VetoAggregator public aggregator;
    L2VetoReceiver public receiver;
    TaikoBridgeMock public bridgeMock;
    TaikoL1Mock public taikoL1;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    address internal immutable OPTIMISTIC_BASE = address(new OptimisticTokenVotingPlugin());
    address internal immutable DAO_BASE = address(new DAO());

    uint64 constant L1_CHAIN_ID = 1;
    uint64 constant L2_CHAIN_ID = 167000;

    uint32 constant MIN_VETO_RATIO = uint32(RATIO_BASE / 10); // 10%
    uint32 constant MIN_DURATION = 4 days;
    uint32 constant TIMELOCK_PERIOD = 1 days;
    uint32 constant L2_INACTIVITY_PERIOD = 10 minutes;
    uint32 constant L2_AGGREGATION_GRACE_PERIOD = 1 days;

    // =========================================================================
    // ACTORS
    // =========================================================================

    address public constant PROPOSER = address(uint160(0xDAA0));
    address public constant TAIKO_ERC20_VAULT = address(0xb61d6e);

    uint256 public constant NUM_L1_VOTERS = 7;
    uint256 public constant NUM_L2_VOTERS = 3;
    uint256 public constant TOTAL_VOTERS = NUM_L1_VOTERS + NUM_L2_VOTERS;

    address[] public l1Voters;
    address[] public l2Voters;
    address[] public allVoters;

    // =========================================================================
    // SETUP
    // =========================================================================

    function setUp() public virtual {
        // 1. Deploy DAO
        dao = DAO(
            payable(
                createProxyAndCall(DAO_BASE, abi.encodeCall(DAO.initialize, ("", address(this), address(0), "")))
            )
        );

        // 2. Deploy voting token
        votingToken = new GovernanceERC20Mock(address(dao));

        // 3. Create actors and mint tokens
        _createActors();

        // 4. Deploy TaikoL1 mock and bridge mock
        taikoL1 = new TaikoL1Mock();
        bridgeMock = new TaikoBridgeMock();

        // 5. Deploy OptimisticTokenVotingPlugin
        OptimisticTokenVotingPlugin.OptimisticGovernanceSettings memory settings = OptimisticTokenVotingPlugin
            .OptimisticGovernanceSettings({
            minVetoRatio: MIN_VETO_RATIO,
            minDuration: MIN_DURATION,
            timelockPeriod: TIMELOCK_PERIOD,
            l2InactivityPeriod: L2_INACTIVITY_PERIOD,
            l2AggregationGracePeriod: L2_AGGREGATION_GRACE_PERIOD,
            skipL2: false
        });

        plugin = OptimisticTokenVotingPlugin(
            createProxyAndCall(
                OPTIMISTIC_BASE,
                abi.encodeCall(
                    OptimisticTokenVotingPlugin.initialize,
                    (dao, settings, votingToken, address(taikoL1), TAIKO_ERC20_VAULT)
                )
            )
        );

        // 6. Deploy L2VetoReceiver (needs plugin address)
        receiver = new L2VetoReceiver(IDAO(address(dao)), address(bridgeMock), L2_CHAIN_ID, address(plugin));

        // 7. Deploy L2VetoAggregator (needs receiver address)
        aggregator = new L2VetoAggregator(address(bridgeMock), L1_CHAIN_ID, address(votingToken), address(receiver));

        // 8. Wire up permissions and references
        _configurePermissions();

        // 9. Advance 1 block so getPastVotes/getPastTotalSupply work
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(plugin), "Plugin");
        vm.label(address(votingToken), "VotingToken");
        vm.label(address(aggregator), "L2VetoAggregator");
        vm.label(address(receiver), "L2VetoReceiver");
        vm.label(address(bridgeMock), "BridgeMock");
        vm.label(address(taikoL1), "TaikoL1");
        vm.label(TAIKO_ERC20_VAULT, "ERC20Vault");
        vm.label(PROPOSER, "Proposer");
    }

    function _createActors() internal {
        // L1 voters: hold tokens directly (self-delegated)
        for (uint256 i = 0; i < NUM_L1_VOTERS; i++) {
            address voter = address(uint160(0x1000 + i));
            l1Voters.push(voter);
            allVoters.push(voter);
            vm.label(voter, string.concat("L1Voter", vm.toString(i)));

            // Varying power: 1000, 2000, ..., 7000 tokens
            uint256 power = (i + 1) * 1000 ether;
            votingToken.mintAndDelegate(voter, power);
        }

        // L2 voters: tokens are on L2 (represented by ERC20Vault holding on L1)
        // We also mint them directly for L2 aggregator voting power lookups
        for (uint256 i = 0; i < NUM_L2_VOTERS; i++) {
            address voter = address(uint160(0x2000 + i));
            l2Voters.push(voter);
            allVoters.push(voter);
            vm.label(voter, string.concat("L2Voter", vm.toString(i)));

            // Varying power: 500, 1000, 1500 tokens
            uint256 power = (i + 1) * 500 ether;
            votingToken.mintAndDelegate(voter, power);
        }

        // Mint to the ERC20Vault to represent bridged L2 voting power
        // Sum of L2 voter power: 500 + 1000 + 1500 = 3000
        votingToken.mintAndDelegate(TAIKO_ERC20_VAULT, 3000 ether);
    }

    function _configurePermissions() internal {
        // Plugin can execute on DAO
        dao.grant(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());

        // Proposer can create proposals
        dao.grant(address(plugin), PROPOSER, plugin.PROPOSER_PERMISSION_ID());

        // Set l2VetoReceiver on plugin
        dao.grant(address(plugin), address(this), plugin.UPDATE_L2_VETO_RECEIVER_PERMISSION_ID());
        plugin.setL2VetoReceiver(address(receiver));
        dao.revoke(address(plugin), address(this), plugin.UPDATE_L2_VETO_RECEIVER_PERMISSION_ID());

        // Set trustedL2Aggregator on receiver
        dao.grant(address(receiver), address(this), receiver.SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID());
        receiver.setTrustedL2Aggregator(address(aggregator));
        dao.revoke(address(receiver), address(this), receiver.SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID());

        // Transfer DAO root to itself (cleanup)
        dao.grant(address(dao), address(dao), dao.ROOT_PERMISSION_ID());
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());
    }
}
