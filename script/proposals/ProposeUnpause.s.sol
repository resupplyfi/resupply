// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract ProposeUnpause is BaseProposal {
    IResupplyPair public pair = IResupplyPair(Protocol.PAIR_CURVELEND_SFRXUSD_CRVUSD);

    function run() public isBatch(deployer) {
        require(pair.borrowLimit() == 0, "Pair not paused");
        deployMode = DeployMode.FORK;

        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Unpause sfrxUSD/crvUSD pair");

        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](1);
        actions[0] = IVoter.Action({
            target: Protocol.PAIR_CURVELEND_SFRXUSD_CRVUSD,
            data: abi.encodeWithSelector(IResupplyPair.unpause.selector)
        });
    }
}
