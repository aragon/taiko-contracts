// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {L2VetoReceiver} from "../../src/crosschain/L2VetoReceiver.sol";
import {IBridge} from "../../src/interfaces/IBridge.sol";
import {TaikoHelper} from "../helpers/TaikoHelper.sol";
import {createProxyAndCall} from "../../src/helpers/proxy.sol";

/// @notice Fork tests using TaikoHelper to simulate cross-chain messages
/// @dev These tests require environment variables to be set:
///      - L1_RPC_URL: RPC URL for L1 (e.g., Ethereum mainnet or Hoodi)
///      - L2_RPC_URL: RPC URL for L2 (e.g., Taiko mainnet or TaikoHoodi)
///      - L1_TAIKO_BRIDGE: Address of the Taiko Bridge on L1
///      - L2_TAIKO_BRIDGE: Address of the Taiko Bridge on L2
///      - L2_CHAIN_ID: Chain ID of the L2 network
contract L2VetoReceiverForkTest is Test {
    // Fork IDs
    uint256 public l1Fork;
    uint256 public l2Fork;

    // Addresses (from environment)
    address public l1Bridge;
    address public l2Bridge;

    TaikoHelper public taikoHelper;
    L2VetoReceiver public receiver;

    address public trustedAggregator;
    uint64 public l2ChainId;

    bool public forksAvailable;

    function setUp() public {
        // Skip if RPC URLs not set
        string memory l1Rpc = vm.envOr("L1_RPC_URL", string(""));
        string memory l2Rpc = vm.envOr("L2_RPC_URL", string(""));

        if (bytes(l1Rpc).length == 0 || bytes(l2Rpc).length == 0) {
            forksAvailable = false;
            return;
        }

        forksAvailable = true;

        l1Fork = vm.createFork(l1Rpc);
        l2Fork = vm.createFork(l2Rpc);

        l1Bridge = vm.envAddress("L1_TAIKO_BRIDGE");
        l2Bridge = vm.envAddress("L2_TAIKO_BRIDGE");
        l2ChainId = uint64(vm.envUint("L2_CHAIN_ID"));

        // Deploy mock addresses (would be real in production)
        trustedAggregator = address(0x1234567890123456789012345678901234567890);
        address mockVotingPlugin = makeAddr("mockVotingPlugin");

        vm.selectFork(l1Fork);

        DAO dao = DAO(
            payable(
                createProxyAndCall(address(new DAO()), abi.encodeCall(DAO.initialize, ("", address(this), address(0), "")))
            )
        );
        receiver = new L2VetoReceiver(IDAO(address(dao)), l1Bridge, l2ChainId, mockVotingPlugin);
        dao.grant(address(receiver), address(this), receiver.SET_TRUSTED_L2_AGGREGATOR_PERMISSION_ID());
        receiver.setTrustedL2Aggregator(trustedAggregator);

        taikoHelper = new TaikoHelper();
    }

    modifier skipIfNoForks() {
        if (!forksAvailable) {
            return;
        }
        _;
    }

    function test_forkSetup() public skipIfNoForks {
        vm.selectFork(l1Fork);
        assertEq(receiver.bridge(), l1Bridge);
        assertEq(receiver.l2ChainId(), l2ChainId);
    }

    function test_l1BridgeExists() public skipIfNoForks {
        vm.selectFork(l1Fork);

        // Check that the bridge contract has code
        uint256 codeSize;
        address bridgeAddr = l1Bridge;
        assembly {
            codeSize := extcodesize(bridgeAddr)
        }
        assertGt(codeSize, 0, "L1 Bridge should have code");
    }

    function test_l2BridgeExists() public skipIfNoForks {
        vm.selectFork(l2Fork);

        // Check that the bridge contract has code
        uint256 codeSize;
        address bridgeAddr = l2Bridge;
        assembly {
            codeSize := extcodesize(bridgeAddr)
        }
        assertGt(codeSize, 0, "L2 Bridge should have code");
    }

    // Additional fork tests would simulate actual bridge message relay
    // using TaikoHelper.relay() or TaikoHelper.relayMessageLocal()
    //
    // Example flow:
    // 1. On L2 fork: L2VetoAggregator calls bridge.sendMessage()
    // 2. Record logs with vm.recordLogs()
    // 3. Use taikoHelper.relay() to simulate message delivery on L1
    // 4. Verify L2VetoReceiver has stored the veto tally
}
