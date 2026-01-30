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
    address public constant OPERATOR = Prisma.PRISMA_FEE_FORWARDER;
    string public constant REGISTRY_KEY = "PRISMA_VECRV_OPERATOR";

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Set Prisma veCRV operator");

        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](4);
        actions[0] = IVoter.Action({
            target: Prisma.VOTER_PROXY,
            data: abi.encodeWithSelector(
                IPrismaVoterProxy.setDepositManager.selector,
                OPERATOR
            )
        });
        actions[1] = IVoter.Action({
            target: Prisma.VOTER_PROXY,
            data: abi.encodeWithSelector(
                IPrismaVoterProxy.setVoteManager.selector,
                OPERATOR
            )
        });
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
        actions[3] = IVoter.Action({
            target: Protocol.CORE,
            data: abi.encodeWithSelector(
                ICore.execute.selector,
                Protocol.REGISTRY,
                abi.encodeWithSelector(IResupplyRegistry.setAddress.selector, REGISTRY_KEY, OPERATOR)
            )
        });

        // on-chain approval for boost delegation (execute via prisma voter)
        actions = _appendApprove(actions);
    }

    function _appendApprove(IVoter.Action[] memory actions) internal view returns (IVoter.Action[] memory out) {
        out = new IVoter.Action[](actions.length + 1);
        for (uint256 i = 0; i < actions.length; i++) {
            out[i] = actions[i];
        }
        out[actions.length] = IVoter.Action({
            target: Prisma.VOTER_PROXY,
            data: abi.encodeWithSelector(
                IPrismaVoterProxy.execute.selector,
                Mainnet.CURVE_BOOST_DELEGATION,
                abi.encodeWithSelector(IVeBoost.approve.selector, OPERATOR, type(uint256).max)
            )
        });
    }
}
