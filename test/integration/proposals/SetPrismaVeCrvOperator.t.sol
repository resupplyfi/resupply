// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { Protocol, Prisma, Mainnet } from "src/Constants.sol";
import { PrismaVeCrvOperator } from "src/dao/operators/PrismaVeCrvOperator.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVeBoost } from "src/interfaces/curve/IVeBoost.sol";
import { SetPrismaVeCrvOperator } from "script/proposals/SetPrismaVeCrvOperator.s.sol";

contract SetPrismaVeCrvOperatorTest is BaseProposalTest {
    SetPrismaVeCrvOperator public script;

    function setUp() public override {
        super.setUp();
        script = new SetPrismaVeCrvOperator();
        uint256 proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_PrimsaVeCrvOperatorSetup() public {
        address operator = script.OPERATOR();

        assertEq(IPrismaVoterProxy(Prisma.VOTER_PROXY).depositManager(), operator, "deposit manager not updated");
        assertEq(IPrismaVoterProxy(Prisma.VOTER_PROXY).voteManager(), operator, "vote manager not updated");

        (bool authorized,) = ICore(Protocol.CORE).operatorPermissions(
            operator,
            Prisma.VOTER_PROXY,
            IPrismaVoterProxy.execute.selector
        );
        assertTrue(authorized, "execute permission not set");

        address registryAddr = IResupplyRegistry(Protocol.REGISTRY).getAddress("PRISMA_VECRV_OPERATOR");
        assertEq(registryAddr, operator, "registry key not set");

        uint256 allowance = IVeBoost(Mainnet.CURVE_BOOST_DELEGATION).allowance(Prisma.VOTER_PROXY, operator);
        assertEq(allowance, type(uint256).max, "boost allowance not set");
    }
}
