// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Setup } from "test/e2e/Setup.sol";
import { BorrowLimitController } from "src/dao/operators/BorrowLimitController.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { console2 } from "forge-std/console2.sol";

contract BorrowLimitControllerTest is Setup {
    BorrowLimitController public borrowController;

    function setUp() public override {
        super.setUp();
        deployDefaultLendingPairs();
        
        // Deploy controller
        borrowController = new BorrowLimitController(address(core));

        // Set permissions for the controller to call setBorrowLimit on pairs
        vm.startPrank(address(core));
        core.setOperatorPermissions(
            address(borrowController),
            address(0), // address(0) means any address
            IResupplyPair.setBorrowLimit.selector,
            true,
            IAuthHook(address(0))
        );
        vm.stopPrank();

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
        borrowController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        (uint256 targetBorrowLimit, uint256 prevBorrowLimit, uint64 startTime, uint64 endTimeStored) = borrowController.pairLimits(address(testPair));
        
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
        borrowController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);
    }

    function test_SetPairBorrowLimitRampCanOnlyRampUp() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 lowerBorrowLimit = initialBorrowLimit / 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        vm.expectRevert("can only ramp up");
        borrowController.setPairBorrowLimitRamp(address(testPair), lowerBorrowLimit, endTime);
    }

    function test_SetPairBorrowLimitRampRateLimit() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 6 days; // Less than 7 days

        vm.prank(address(core));
        vm.expectRevert("rate of change too high");
        borrowController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);
    }

    function test_UpdatePairBorrowLimit() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        // Skip 5 days (50% of the ramp period)
        skip(5 days);

        uint256 previewAmt = borrowController.previewNewBorrowLimit(address(testPair));
        borrowController.updatePairBorrowLimit(address(testPair));
        assertEq(previewAmt, testPair.borrowLimit(), "Preview borrow limit not correct");
        uint256 currentBorrowLimit = testPair.borrowLimit();
        uint256 expectedBorrowLimit = initialBorrowLimit + ((newBorrowLimit - initialBorrowLimit) * 5000) / 10000;
        
        assertApproxEqRel(currentBorrowLimit, expectedBorrowLimit, 0.01e18, "Borrow limit not updated correctly");
    }

    function test_UpdatePairBorrowLimitNoRampInfo() public {
        vm.expectRevert("no ramp info");
        borrowController.updatePairBorrowLimit(address(testPair));
    }

    function test_UpdatePairBorrowLimitAlreadyFinished() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        // Skip past the end time
        skip(11 days);

        // First update should work and mark as finished
        uint256 previewAmt = borrowController.previewNewBorrowLimit(address(testPair));
        borrowController.updatePairBorrowLimit(address(testPair));
        assertEq(previewAmt, testPair.borrowLimit(), "Preview borrow limit not correct");

        // Second update should fail due to start time being cleared from prior update
        vm.expectRevert("no ramp info");
        borrowController.updatePairBorrowLimit(address(testPair));
    }

    function test_UpdatePairBorrowLimitOutsideRange() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        // Manually change the borrow limit outside the expected range
        vm.prank(address(core));
        testPair.setBorrowLimit(newBorrowLimit * 2);

        vm.expectRevert("current borrow limit outside of range");
        borrowController.updatePairBorrowLimit(address(testPair));
    }

    function test_CancelRamp() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        vm.prank(address(core));
        borrowController.cancelRamp(address(testPair));

        (uint256 targetBorrowLimit, uint256 prevBorrowLimit, uint64 startTime, uint64 endTimeStored) = borrowController.pairLimits(address(testPair));
        
        assertEq(targetBorrowLimit, 0, "Target borrow limit should be reset");
        assertEq(prevBorrowLimit, 0, "Previous borrow limit should be reset");
        assertEq(startTime, 0, "Start time should be reset");
        assertEq(endTimeStored, 0, "End time should be reset");
    }

    function test_CancelRampOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("!core");
        borrowController.cancelRamp(address(testPair));
    }

    function test_CompleteRamp() public {
        uint256 initialBorrowLimit = testPair.borrowLimit();
        uint256 newBorrowLimit = initialBorrowLimit * 2;
        uint256 endTime = vm.getBlockTimestamp() + 10 days;

        vm.prank(address(core));
        borrowController.setPairBorrowLimitRamp(address(testPair), newBorrowLimit, endTime);

        // Skip to end
        skip(10 days);
        borrowController.updatePairBorrowLimit(address(testPair));

        uint256 finalBorrowLimit = testPair.borrowLimit();
        assertEq(finalBorrowLimit, newBorrowLimit, "Should reach target borrow limit");

        (,,uint64 startTime,) = borrowController.pairLimits(address(testPair));
        assertEq(startTime, 0, "Should be marked as finished by 0 in starttime");
    }
} 