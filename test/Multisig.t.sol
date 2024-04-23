// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {StandardProposalCondition} from "../src/conditions/StandardProposalCondition.sol";
import {OptimisticTokenVotingPlugin} from "../src/OptimisticTokenVotingPlugin.sol";
import {Multisig} from "../src/Multisig.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";
import {ERC20VotesMock} from "./mocks/ERC20VotesMock.sol";
import {RATIO_BASE, RatioOutOfBounds} from "@aragon/osx/plugins/utils/Ratio.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {createProxyAndCall} from "./common.sol";

contract StandardProposalConditionTest is Test {
    address immutable daoBase = address(new DAO());
    address immutable multisigBase = address(new Multisig());
    address immutable optimisticBase =
        address(new OptimisticTokenVotingPlugin());
    address immutable votingTokenBase = address(new ERC20VotesMock());

    address immutable alice = address(0xa11ce);
    address immutable bob = address(0xB0B);
    address immutable carol = address(0xc4601);
    address immutable david = address(0xd471d);
    address immutable randomWallet = vm.addr(1234567890);

    DAO dao;
    Multisig plugin;
    OptimisticTokenVotingPlugin optimisticPlugin;

    function setUp() public {
        vm.startPrank(alice);

        // Deploy a DAO with Alice as root
        dao = DAO(
            payable(
                createProxyAndCall(
                    address(daoBase),
                    abi.encodeCall(
                        DAO.initialize,
                        ("", alice, address(0x0), "")
                    )
                )
            )
        );

        {
            // Deploy ERC20 token
            ERC20VotesMock votingToken = ERC20VotesMock(
                createProxyAndCall(
                    address(votingTokenBase),
                    abi.encodeCall(ERC20VotesMock.initialize, ())
                )
            );
            // Deploy a target contract for passed proposals to be created in
            OptimisticTokenVotingPlugin.OptimisticGovernanceSettings
                memory targetContractSettings = OptimisticTokenVotingPlugin
                    .OptimisticGovernanceSettings({
                        minVetoRatio: uint32(RATIO_BASE / 10),
                        minDuration: 10 days,
                        minProposerVotingPower: 0
                    });

            optimisticPlugin = OptimisticTokenVotingPlugin(
                createProxyAndCall(
                    address(optimisticBase),
                    abi.encodeCall(
                        OptimisticTokenVotingPlugin.initialize,
                        (dao, targetContractSettings, votingToken)
                    )
                )
            );
        }

        {
            // Deploy a new multisig instance
            Multisig.MultisigSettings memory settings = Multisig
                .MultisigSettings({onlyListed: true, minApprovals: 3});
            address[] memory signers = new address[](4);
            signers[0] = alice;
            signers[1] = bob;
            signers[2] = carol;
            signers[3] = david;

            plugin = Multisig(
                createProxyAndCall(
                    address(multisigBase),
                    abi.encodeCall(
                        Multisig.initialize,
                        (dao, signers, settings)
                    )
                )
            );
        }

        // The Multisig can create proposals on the Optimistic plugin
        dao.grant(
            address(optimisticPlugin),
            address(plugin),
            optimisticPlugin.PROPOSER_PERMISSION_ID()
        );
    }
}
