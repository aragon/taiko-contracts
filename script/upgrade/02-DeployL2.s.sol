// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {ScriptBase} from "../lib/ScriptBase.sol";
import {L2VetoAggregator} from "../../src/crosschain/L2VetoAggregator.sol";

/// @title DeployL2 (Upgrade)
/// @notice Deploys L2VetoAggregator on L2.
/// @dev Step 2 of 3. Run against the L2 RPC.
///      Requires VETO_RECEIVER_ADDRESS from step 1.
contract DeployL2 is ScriptBase {
    struct Config {
        uint256 privKey;
        address l2TaikoBridge;
        uint64 l1ChainId;
        address l2VotingToken;
        address vetoReceiver;
    }

    function run() external {
        Config memory config = _loadConfig();

        vm.startBroadcast(config.privKey);

        L2VetoAggregator aggregator = new L2VetoAggregator(
            config.l2TaikoBridge, config.l1ChainId, config.l2VotingToken, config.vetoReceiver
        );
        console.log("L2VetoAggregator:", address(aggregator));
        console.log("  bridge:", config.l2TaikoBridge);
        console.log("  l1ChainId:", config.l1ChainId);
        console.log("  votingToken:", config.l2VotingToken);
        console.log("  l1Receiver (immutable):", config.vetoReceiver);

        vm.stopBroadcast();

        string memory key = "l2";
        string memory json = vm.serializeAddress(key, "l2VetoAggregator", address(aggregator));

        _writeDeployment("upgrade/02-DeployL2.s.sol", json);

        console.log("");
        console.log("Next: run 03-EncodeProposal.s.sol against L1 RPC");
    }

    function _loadConfig() internal view returns (Config memory) {
        return Config({
            privKey: vm.envUint("DEPLOYMENT_PRIVATE_KEY"),
            l2TaikoBridge: vm.envAddress("L2_TAIKO_BRIDGE"),
            l1ChainId: uint64(vm.envUint("L1_CHAIN_ID")),
            l2VotingToken: vm.envAddress("L2_VOTING_TOKEN"),
            vetoReceiver: vm.envAddress("VETO_RECEIVER_ADDRESS")
        });
    }
}
