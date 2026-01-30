// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/e2e/Setup.sol";
import { Prisma, Mainnet, Protocol } from "src/Constants.sol";
import { PrismaVeCrvOperator } from "src/dao/operators/PrismaVeCrvOperator.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";
import { ICurveEscrow } from "src/interfaces/curve/ICurveEscrow.sol";
import { IVeBoost } from "src/interfaces/curve/IVeBoost.sol";
import { ICurveVoting } from "src/interfaces/curve/ICurveVoting.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CurveVoteHelper } from "test/utils/CurveVoteHelper.sol";

contract PrismaVeCrvOperatorTest is Setup, CurveVoteHelper {
    PrismaVeCrvOperator public operator;

    function setUp() public override {
        super.setUp();
        operator = new PrismaVeCrvOperator(address(core));

        vm.prank(Prisma.VOTER_PROXY);
        IVeBoost(Mainnet.CURVE_BOOST_DELEGATION).approve(address(operator), type(uint256).max);

        vm.prank(address(core));
        core.setOperatorPermissions(
            address(operator),
            Prisma.VOTER_PROXY,
            IPrismaVoterProxy.execute.selector,
            true,
            IAuthHook(address(0))
        );

        vm.prank(address(voter));
        core.execute(
            Prisma.VOTER_PROXY,
            abi.encodeWithSelector(IPrismaVoterProxy.setDepositManager.selector, address(operator))
        );

        vm.prank(address(voter));
        core.execute(
            Prisma.VOTER_PROXY,
            abi.encodeWithSelector(IPrismaVoterProxy.setVoteManager.selector, address(operator))
        );

        assertEq(IPrismaVoterProxy(Prisma.VOTER_PROXY).depositManager(), address(operator));
        assertEq(IPrismaVoterProxy(Prisma.VOTER_PROXY).voteManager(), address(operator));
    }

    function test_ClaimFeesVariants() public {
        address receiver = operator.receiver();
        uint256 amount = 1_000e18;
        IERC20 scrvusd = IERC20(Mainnet.SCRVUSD_ERC20);

        deal(Mainnet.CRVUSD_ERC20, Prisma.VOTER_PROXY, amount);
        uint256 receiverBefore = crvusdToken.balanceOf(receiver);
        vm.prank(Protocol.DEPLOYER);
        uint256 claimed = operator.claimFees();

        assertGt(claimed, 0, "claim 1 should be non-zero");
        assertEq(crvusdToken.balanceOf(receiver), receiverBefore + claimed);
        assertEq(crvusdToken.balanceOf(Prisma.VOTER_PROXY), 0);

        deal(Mainnet.CRVUSD_ERC20, Prisma.VOTER_PROXY, amount);
        receiverBefore = scrvusd.balanceOf(receiver);
        vm.prank(Protocol.DEPLOYER);
        claimed = operator.claimFees(true, receiver);

        assertGt(claimed, 0, "claim 2 should be non-zero");
        assertGt(scrvusd.balanceOf(receiver), receiverBefore);
        assertEq(crvusdToken.balanceOf(Prisma.VOTER_PROXY), 0);

    }

    function test_BoostDelegation() public {
        skip(1 weeks);
        IVeBoost boost = IVeBoost(operator.BOOST_DELEGATION());
        uint256 delegableBefore = operator.delegableBalance();
        assertGt(delegableBefore, 0, "no delegable balance");

        uint256 convexBefore = boost.adjusted_balance_of(operator.CONVEX_VOTER());
        uint256 yearnBefore = boost.adjusted_balance_of(operator.YEARN_VOTER());

        vm.prank(Protocol.DEPLOYER);
        operator.delegateBoost();

        uint256 delegableAfter = operator.delegableBalance();
        uint256 convexAfter = boost.adjusted_balance_of(operator.CONVEX_VOTER());
        uint256 yearnAfter = boost.adjusted_balance_of(operator.YEARN_VOTER());

        assertLt(delegableAfter, delegableBefore, "delegable balance not reduced");
        assertGt(convexAfter, convexBefore, "convex boost not increased");
        assertGt(yearnAfter, yearnBefore, "yearn boost not increased");
    }

    function test_ExtendLockWorks() public {
        ICurveEscrow ve = ICurveEscrow(Mainnet.CURVE_ESCROW);
        IPrismaVoterProxy voterProxy = IPrismaVoterProxy(Prisma.VOTER_PROXY);
        uint256 unlockBefore = ve.locked__end(Prisma.VOTER_PROXY);
        skip(2 weeks);
        vm.prank(Protocol.DEPLOYER);
        operator.extendLock();
        uint256 unlockAfter = ve.locked__end(Prisma.VOTER_PROXY);
        assertGt(unlockAfter, unlockBefore, "unlock time not extended");
    }

    function test_VoteViaOperator() public {
        skip(10 days);
        IPrismaVoterProxy.GaugeWeightVote[] memory votes = new IPrismaVoterProxy.GaugeWeightVote[](1);
        votes[0] = IPrismaVoterProxy.GaugeWeightVote({
            gauge: Protocol.REUSD_SCRVUSD_GAUGE,
            weight: 1
        });
        vm.prank(Protocol.DEPLOYER);
        operator.voteForGaugeWeights(votes);
    }

    function test_VoteInCurveDao() public {
        bytes memory script = buildOwnershipScript(
            Protocol.REUSD_SCRVUSD_GAUGE,
            abi.encodeWithSelector(bytes4(keccak256("set_killed(bool)")), false)
        );
        ICurveVoting ownershipVoting = ICurveVoting(Mainnet.CURVE_OWNERSHIP_VOTING);
        vm.prank(Mainnet.CONVEX_VOTEPROXY);
        uint256 proposalId = ownershipVoting.newVote(script, "Test vote", false, false);

        assertTrue(ownershipVoting.canVote(proposalId, Prisma.VOTER_PROXY), "prisma voter cannot vote");
        (,,, , , , uint256 yeaBefore, uint256 nayBefore, ,) = ownershipVoting.getVote(proposalId);

        vm.prank(Protocol.DEPLOYER);
        operator.voteInCurveDao(Mainnet.CURVE_OWNERSHIP_VOTING, proposalId, true);

        (,,, , , , uint256 yeaAfter, uint256 nayAfter, ,) = ownershipVoting.getVote(proposalId);
        assertGt(yeaAfter, yeaBefore, "yea not increased");
        assertEq(nayAfter, nayBefore, "nay changed");
    }

}
