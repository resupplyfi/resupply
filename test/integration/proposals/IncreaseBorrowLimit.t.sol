// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IncreaseBorrowLimit } from "script/proposals/IncreaseBorrowLimit.s.sol";

contract IncreaseBorrowLimitTest is BaseProposalTest {
    IncreaseBorrowLimit public script;
    uint256 public borrowLimitBefore;
    uint256 public targetBorrowLimit;
    uint256 public expectedRampEndTime;

    function setUp() public override {
        super.setUp();
        if (isProposalProcessed(19)) vm.skip(true);
        script = new IncreaseBorrowLimit();

        borrowLimitBefore = IResupplyPair(script.PAIR()).borrowLimit();
        targetBorrowLimit = borrowLimitBefore * 2;
        expectedRampEndTime = block.timestamp + script.RAMP_DURATION();
    }

    function test_BorrowLimitRampConfigured() public {
        _executeProposal();

        IBorrowLimitController.PairBorrowLimit memory ramp = borrowLimitController.pairLimits(script.PAIR());
        uint256 remainingRampDuration = uint256(ramp.endTime) - block.timestamp;

        assertEq(IResupplyPair(script.PAIR()).borrowLimit(), borrowLimitBefore, "borrow limit changed before ramp update");
        assertEq(ramp.prevBorrowLimit, borrowLimitBefore, "prev borrow limit mismatch");
        assertEq(ramp.targetBorrowLimit, targetBorrowLimit, "target borrow limit mismatch");
        assertEq(uint256(ramp.startTime), block.timestamp, "ramp start time mismatch");
        assertEq(uint256(ramp.endTime), expectedRampEndTime, "ramp end time mismatch");
        assertGt(remainingRampDuration, 0, "ramp already ended");

        skip(remainingRampDuration / 2);
        borrowLimitController.updatePairBorrowLimit(script.PAIR());

        uint256 midBorrowLimit = IResupplyPair(script.PAIR()).borrowLimit();
        assertGt(midBorrowLimit, borrowLimitBefore, "borrow limit did not increase mid-ramp");
        assertLt(midBorrowLimit, targetBorrowLimit, "borrow limit reached target too early");

        skip(remainingRampDuration - (remainingRampDuration / 2));
        borrowLimitController.updatePairBorrowLimit(script.PAIR());

        assertEq(IResupplyPair(script.PAIR()).borrowLimit(), targetBorrowLimit, "borrow limit did not reach target");

        ramp = borrowLimitController.pairLimits(script.PAIR());
        assertEq(uint256(ramp.startTime), 0, "ramp start time not cleared");
        assertEq(uint256(ramp.endTime), 0, "ramp end time not cleared");
    }

    function test_OperatorPermissionMigrated() public {
        _assertPreExecutionPermissionState();
        _executeProposal();

        (bool incorrectEnabled,) = core.operatorPermissions(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            Protocol.REDEMPTION_HANDLER,
            IRedemptionHandler.updateGuardSettings.selector
        );
        assertFalse(incorrectEnabled, "incorrect target permission not removed");

        (bool wildcardEnabled,) = core.operatorPermissions(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            address(0),
            IRedemptionHandler.updateGuardSettings.selector
        );
        assertTrue(wildcardEnabled, "wildcard target permission not granted");
    }

    function _assertPreExecutionPermissionState() internal view {
        (bool incorrectEnabled,) = core.operatorPermissions(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            Protocol.REDEMPTION_HANDLER,
            IRedemptionHandler.updateGuardSettings.selector
        );
        assertTrue(incorrectEnabled, "sanity: incorrect permission not enabled before proposal");

        (bool wildcardEnabled,) = core.operatorPermissions(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            address(0),
            IRedemptionHandler.updateGuardSettings.selector
        );
        assertFalse(wildcardEnabled, "sanity: wildcard permission enabled before proposal");
    }

    function _executeProposal() internal {
        uint256 proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }
}
