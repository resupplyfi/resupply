// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { Protocol, Prisma } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";

contract SetPrismaDepositManager is BaseAction, BaseProposal {
    address public constant FORWARDER = Prisma.PRISMA_FEE_FORWARDER;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Set Prisma deposit manager");

        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](1);
        actions[0] = IVoter.Action({
            target: Prisma.VOTER_PROXY,
            data: abi.encodeWithSelector(
                IPrismaVoterProxy.setDepositManager.selector,
                FORWARDER
            )
        });
    }
}
