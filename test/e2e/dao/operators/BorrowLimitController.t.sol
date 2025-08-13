// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/e2e/Setup.sol";

contract BorrowLimitControllerTest is Setup {

    function setUp() public override {
        super.setUp();
        deployDefaultLendingPairs();

        // Initial borrow limit > 0 is needed
        vm.startPrank(address(core));
        testPair.setBorrowLimit(1_000_000e18);
        testPair2.setBorrowLimit(1_000_000e18);
        vm.stopPrank();
    }

    function test_SetPairBorrowLimitRamp() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowLimitController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        (uint256 targetBorrowLimit, uint256 prevBorrowLimit, uint64 startTime, uint64 endTimeStored) = borrowLimitController.pairLimits(address(testPair));
        
        assertEq(targetBorrowLimit, newBorrowLimit, "Target borrow limit not set correctly");
        assertEq(prevBorrowLimit, initialBorrowLimit, "Previous borrow limit not set correctly");
        assertEq(startTime, uint64(vm.getBlockTimestamp()), "Start time not set correctly");
        assertEq(endTimeStored, uint64(endTime), "End time not set correctly");
    }

    function test_SetPairBorrowLimitRampOnlyOwner() public {
        uint256 newBorrowLimit = 100_000e18;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(user1);
        vm.expectRevert("!core");
        borrowLimitController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);
    }

    function test_SetPairBorrowLimitRampCanOnlyRampUp() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 lowerBorrowLimit = initialBorrowLimit / 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        vm.expectRevert("can only ramp up");
        borrowLimitController.setPairBorrowLimitRamp(address(testPair), lowerBorrowLimit, endTime);
    }

    function test_SetPairBorrowLimitRampRateLimit() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 6 days; // Less than 7 days

        vm.prank(address(core));
        vm.expectRevert("rate of change too high");
        borrowLimitController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);
    }

    function test_UpdatePairBorrowLimit() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowLimitController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        // Skip 5 days (50% of the ramp period)
        skip(5 days);

        uint256 previewAmt = borrowLimitController.previewNewBorrowLimit(address(testPair));
        borrowLimitController.updatePairBorrowLimit(address(testPair));
        assertEq(previewAmt, testPair.borrowLimit(), "Preview borrow limit not correct");
        uint256 currentBorrowLimit = testPair.borrowLimit();
        uint256 expectedBorrowLimit = initialBorrowLimit + ((newBorrowLimit - initialBorrowLimit) * 5000) / 10000;
        
        assertApproxEqRel(currentBorrowLimit, expectedBorrowLimit, 0.01e18, "Borrow limit not updated correctly");
    }

    function test_UpdatePairBorrowLimitNoRampInfo() public {
        vm.expectRevert("no ramp info");
        borrowLimitController.updatePairBorrowLimit(address(testPair));
    }

    function test_UpdatePairBorrowLimitAlreadyFinished() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowLimitController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        // Skip past the end time
        skip(11 days);

        // First update should work and mark as finished
        uint256 previewAmt = borrowLimitController.previewNewBorrowLimit(address(testPair));
        borrowLimitController.updatePairBorrowLimit(address(testPair));
        assertEq(previewAmt, testPair.borrowLimit(), "Preview borrow limit not correct");

        // Second update should fail due to start time being cleared from prior update
        vm.expectRevert("no ramp info");
        borrowLimitController.updatePairBorrowLimit(address(testPair));
    }

    function test_UpdatePairBorrowLimitOutsideRange() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowLimitController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        // Manually change the borrow limit outside the expected range
        vm.prank(address(core));
        testPair.setBorrowLimit(newBorrowLimit * 2);

        vm.expectRevert("current borrow limit outside of range");
        borrowLimitController.updatePairBorrowLimit(address(testPair));
    }

    function test_CancelRamp() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowLimitController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        vm.prank(address(core));
        borrowLimitController.cancelRamp(address(testPair));

        (uint256 targetBorrowLimit, uint256 prevBorrowLimit, uint64 startTime, uint64 endTimeStored) = borrowLimitController.pairLimits(address(testPair));
        
        assertEq(targetBorrowLimit, 0, "Target borrow limit should be reset");
        assertEq(prevBorrowLimit, 0, "Previous borrow limit should be reset");
        assertEq(startTime, 0, "Start time should be reset");
        assertEq(endTimeStored, 0, "End time should be reset");
    }

    function test_CancelRampOnlyOwner() public {
        vm.prank(address(1));
        vm.expectRevert("!core");
        borrowLimitController.cancelRamp(address(testPair));
    }

    function test_CompleteRamp() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowLimitController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        // Skip to end
        skip(10 days);
        borrowLimitController.updatePairBorrowLimit(address(testPair));

        uint256 finalBorrowLimit = testPair.borrowLimit();
        assertEq(finalBorrowLimit, newBorrowLimit, "Should reach target borrow limit");

        (,,uint64 startTime,) = borrowLimitController.pairLimits(address(testPair));
        assertEq(startTime, 0, "Should be marked as finished by 0 in starttime");
    }
} 