// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { Protocol, Prisma, Mainnet } from "src/Constants.sol";
import { VeCrvOperator } from "src/dao/operators/VeCrvOperator.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVeBoost } from "src/interfaces/curve/IVeBoost.sol";
import { ICurveEscrow } from "src/interfaces/curve/ICurveEscrow.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ProposeVeCrvOperator } from "script/proposals/ProposeVeCrvOperator.s.sol";

contract ProposeVeCrvOperatorTest is BaseProposalTest {
    ProposeVeCrvOperator public script;

    function _operator() internal view returns (VeCrvOperator operator) {
        address operatorAddress = script.OPERATOR();
        require(operatorAddress.code.length > 0, "VECRV_OPERATOR not deployed");
        operator = VeCrvOperator(operatorAddress);
    }

    function setUp() public override {
        super.setUp();
        script = new ProposeVeCrvOperator();
        uint256 proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_VeCrvOperatorSetup() public {
        address operator = script.OPERATOR();
        assertGt(operator.code.length, 0, "VECRV_OPERATOR not deployed");

        assertEq(IPrismaVoterProxy(Prisma.VOTER_PROXY).depositManager(), operator, "deposit manager not updated");
        assertEq(IPrismaVoterProxy(Prisma.VOTER_PROXY).voteManager(), operator, "vote manager not updated");

        (bool authorized,) = ICore(Protocol.CORE).operatorPermissions(
            operator,
            Prisma.VOTER_PROXY,
            IPrismaVoterProxy.execute.selector
        );
        assertTrue(authorized, "execute permission not set");

        address registryAddr = IResupplyRegistry(Protocol.REGISTRY).getAddress("VECRV_OPERATOR");
        assertEq(registryAddr, operator, "registry key not set");

        uint256 allowance = IVeBoost(Mainnet.CURVE_BOOST_DELEGATION).allowance(Prisma.VOTER_PROXY, operator);
        assertEq(allowance, type(uint256).max, "boost allowance not set");
    }

    function test_ClaimFeesWorksAfterProposal() public {
        VeCrvOperator operator = _operator();
        address receiver = operator.receiver();

        uint256 amount = 1_000e18;
        IERC20 crvusd = IERC20(Mainnet.CRVUSD_ERC20);
        deal(Mainnet.CRVUSD_ERC20, Prisma.VOTER_PROXY, amount);

        uint256 receiverBefore = crvusd.balanceOf(receiver);
        vm.prank(Protocol.DEPLOYER);
        uint256 claimed = operator.claimFees();
        uint256 receiverAfter = crvusd.balanceOf(receiver);

        assertGt(claimed, 0, "claimed amount is zero");
        assertEq(receiverAfter - receiverBefore, claimed, "receiver did not get claimed amount");
        assertEq(crvusd.balanceOf(Prisma.VOTER_PROXY), 0, "voter proxy balance not drained");
    }

    function test_ExtendLockWorksAfterProposal() public {
        VeCrvOperator operator = _operator();
        ICurveEscrow ve = ICurveEscrow(Mainnet.CURVE_ESCROW);

        uint256 unlockBefore = ve.locked__end(Prisma.VOTER_PROXY);
        skip(2 weeks);

        vm.prank(Protocol.DEPLOYER);
        operator.extendLock();

        uint256 unlockAfter = ve.locked__end(Prisma.VOTER_PROXY);
        assertGt(unlockAfter, unlockBefore, "unlock time not extended");
    }
}
