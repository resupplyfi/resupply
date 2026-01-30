// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { Protocol, Prisma, Mainnet } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVeBoost } from "src/interfaces/curve/IVeBoost.sol";

contract SetPrismaVeCrvOperator is BaseAction, BaseProposal {
    address public constant OPERATOR = Prisma.PRISMA_VECRV_OPERATOR;
    string public constant REGISTRY_KEY = "PRISMA_VECRV_OPERATOR";

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Setup Operator for Prisma veCRV");

        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](5);

        // Set Operator as deposit manager, allowing it to pull crvUSD
        actions[0] = IVoter.Action({
            target: Prisma.VOTER_PROXY,
            data: abi.encodeWithSelector(
                IPrismaVoterProxy.setDepositManager.selector,
                OPERATOR
            )
        });

        // Set operator as Vote Manager
        actions[1] = IVoter.Action({
            target: Prisma.VOTER_PROXY,
            data: abi.encodeWithSelector(
                IPrismaVoterProxy.setVoteManager.selector,
                OPERATOR
            )
        });

        // Approve Operator to call .execute() on Prisma voter
        actions[2] = IVoter.Action({
            target: Protocol.CORE,
            data: abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                OPERATOR,
                Prisma.VOTER_PROXY,
                IPrismaVoterProxy.execute.selector,
                true,
                address(0)
            )
        });

        // Approve operator to spend boost
        actions[3] = IVoter.Action({
            target: Prisma.VOTER_PROXY,
            data: abi.encodeWithSelector(
                IPrismaVoterProxy.execute.selector,
                Mainnet.CURVE_BOOST_DELEGATION,
                abi.encodeWithSelector(IVeBoost.approve.selector, OPERATOR, type(uint256).max)
            )
        });

        // Add registry key: "PRISMA_VECRV_OPERATOR"
        actions[4] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector, 
                REGISTRY_KEY, 
                OPERATOR
            )
        });
    }
}
