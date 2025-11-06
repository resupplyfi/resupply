// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { Protocol } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { AdjustBorrowLimits } from "script/proposals/AdjustBorrowLimits.s.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";

contract AdjustBorrowLimitsTest is BaseProposalTest {
    AdjustBorrowLimits public script;

    function setUp() public override {
        super.setUp();
        borrowLimitController = IBorrowLimitController(Protocol.BORROW_LIMIT_CONTROLLER);
        script = new AdjustBorrowLimits();
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_DecreasingPairsUpdated() public {
        AdjustBorrowLimits.PairData[] memory pairData = script.getPairData();
        for (uint256 i = 0; i < pairData.length; i++) {
            AdjustBorrowLimits.PairData memory pair = pairData[i];
            if (pair.targetLimit == 0) {    
                assertEq(IResupplyPair(pair.pair).borrowLimit(), pair.targetLimit);
            }
            else {
                borrowLimitController.updatePairBorrowLimit(pair.pair);
                assertLt(IResupplyPair(pair.pair).borrowLimit(), pair.targetLimit, "Pair due to ramp should be less than target limit");
            }
        }
    }

    function test_IncreasingPairsUpdated() public {
        AdjustBorrowLimits.PairData[] memory pairData = script.getPairData();
        uint256 numPairs = 0;
        uint256 i;
        for (; i < pairData.length; i++) {
            if (pairData[i].targetLimit > 0) {
                pairs[numPairs++] = pairData[i].pair;
            }
        }
        // Build a list of only increasing pairs
        AdjustBorrowLimits.PairData[] memory pairs = new AdjustBorrowLimits.PairData[](numPairs);
        uint256 index = 0;
        i = 0;
        for (; i < pairData.length; i++) {
            if (pairData[i].targetLimit > 0) {
                pairs[index++] = pairData[i];
            }
        }
        uint256 currentLimit;

        // Ramp the borrow limits for all pairs that are increasing
        while (block.timestamp < script.rampEndTime()) {
            for (uint256 i = 0; i < pairs.length; i++) {
                borrowLimitController.updatePairBorrowLimit(pairs[i].pair);
                assertGt(IResupplyPair(pairs[i].pair).borrowLimit(), currentLimit, "Active ramp should be greater than previous limit");
                assertLt(IResupplyPair(pairs[i].pair).borrowLimit(), pairs[i].targetLimit, "Active ramp should be less than target limit");
                currentLimit = IResupplyPair(pairs[i].pair).borrowLimit();
            }
            skip(1 days);
        }

        // Check that the borrow limits are at the target limits
        for (uint256 i = 0; i < pairs.length; i++) {
            borrowLimitController.updatePairBorrowLimit(pairs[i].pair);
            assertEq(IResupplyPair(pairs[i].pair).borrowLimit(), pairs[i].targetLimit, "Borrow limit should be at target limit after ramp");
        }
    }
}