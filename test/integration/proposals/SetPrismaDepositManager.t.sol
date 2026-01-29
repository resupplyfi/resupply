// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { Prisma } from "src/Constants.sol";
import { PrismaFeeForwarder } from "src/dao/operators/PrismaFeeForwarder.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";
import { SetPrismaDepositManager } from "script/proposals/SetPrismaDepositManager.s.sol";

contract SetPrismaDepositManagerTest is BaseProposalTest {
    uint256 public constant PROP_ID = 0;
    SetPrismaDepositManager public script;

    function setUp() public override {
        super.setUp();
        // if (isProposalProcessed(PROP_ID)) return;
        script = new SetPrismaDepositManager();
        uint256 proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_DepositManagerUpdated() public {
        // if (isProposalProcessed(PROP_ID)) return;
        address depositManager = IPrismaVoterProxy(Prisma.VOTER_PROXY).depositManager();
        assertEq(depositManager, script.FORWARDER(), "deposit manager not updated");
    }

    function test_ForwarderClaimIncreasesReceiverBalance() public {
        // if (isProposalProcessed(PROP_ID)) return;
        PrismaFeeForwarder forwarder = PrismaFeeForwarder(script.FORWARDER());
        uint256 amount = 1_000e18;

        deal(address(crvusdToken), Prisma.VOTER_PROXY, amount);
        address receiver = forwarder.receiver();
        uint256 receiverBefore = crvusdToken.balanceOf(receiver);

        uint256 claimed = forwarder.claimFees();
        assertGt(claimed, 0, "claim should be non-zero");
        assertEq(crvusdToken.balanceOf(receiver), receiverBefore + claimed);
    }
}
