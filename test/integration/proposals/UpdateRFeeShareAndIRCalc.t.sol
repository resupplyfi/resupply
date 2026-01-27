// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { Protocol } from "src/Constants.sol";
import { UpdateRFeeShareAndIRCalc } from "script/proposals/UpdateRFeeShareAndIRCalc.s.sol";

contract UpdateRFeeShareAndIRCalcTest is BaseProposalTest {
    uint256 public constant PROP_ID = 15;
    UpdateRFeeShareAndIRCalc public script;
    address public samplePair;
    address public oldRateCalculator;
    uint256 public oldProtocolRedemptionFee;

    function setUp() public override {
        super.setUp();
        if (isProposalProcessed(PROP_ID)) return;
        testPair = IResupplyPair(pairs[5]);
        oldRateCalculator = IResupplyPair(address(testPair)).rateCalculator();
        oldProtocolRedemptionFee = IResupplyPair(address(testPair)).protocolRedemptionFee();
        vm.prank(Protocol.CORE);
        voter.setQuorumPct(1);
        script = new UpdateRFeeShareAndIRCalc();
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_RateCalculatorsUpdated() public {
        if (isProposalProcessed(PROP_ID)) return;
        for (uint256 i = 0; i < pairs.length; i++) {
            assertEq(
                address(IResupplyPair(pairs[i]).rateCalculator()),
                Protocol.INTEREST_RATE_CALCULATOR_V2_1,
                "rate calculator not updated"
            );
        }
        assertNotEq(
            oldRateCalculator,
            Protocol.INTEREST_RATE_CALCULATOR_V2_1,
            "old calculator matches new"
        );
    }

    function test_RedemptionFeeUpdated() public {
        if (isProposalProcessed(PROP_ID)) return;
        for (uint256 i = 0; i < pairs.length; i++) {
            assertEq(
                IResupplyPair(pairs[i]).protocolRedemptionFee(),
                script.newProtocolRedemptionFee(),
                "protocol redemption fee not updated"
            );
        }
        assertNotEq(oldProtocolRedemptionFee, 0.05e18, "old fee matches new");
    }

}
