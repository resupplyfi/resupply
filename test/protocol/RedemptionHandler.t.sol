// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { Setup } from "test/Setup.sol";
import { MockOracle } from "test/mocks/MockOracle.sol";

contract RedemptionHandlerTest is Setup {
    MockOracle mockOracle;

    function setUp() public override {
        super.setUp();
        deployDefaultLendingPairs();
        mockOracle = new MockOracle("Mock Oracle", 1e18);
    }

    function test_SetBaseRedemptionFee() public {
        vm.startPrank(address(core));
        uint256 newFee = 5e16; // 5%
        redemptionHandler.setBaseRedemptionFee(newFee);
        assertEq(redemptionHandler.baseRedemptionFee(), newFee);
        vm.stopPrank();
    }

    function test_SetDiscountInfo() public {
        vm.startPrank(address(core));
        uint256 newRate = 2e17;
        uint256 newMaxUsage = 4e17;
        uint256 newMaxDiscount = 1e14;
        redemptionHandler.setDiscountInfo(newRate, newMaxUsage, newMaxDiscount);
        assertEq(redemptionHandler.usageDecayRate(), newRate);
        assertEq(redemptionHandler.maxUsage(), newMaxUsage);
        assertEq(redemptionHandler.maxDiscount(), newMaxDiscount);
        vm.stopPrank();
    }

    function test_SetUnderlyingOracle() public {
        vm.startPrank(address(core));
        redemptionHandler.setUnderlyingOracle(address(mockOracle));
        assertEq(redemptionHandler.underlyingOracle(), address(mockOracle));
        vm.stopPrank();
    }

    function test_AccessControl() public {
        vm.expectRevert("!core");
        redemptionHandler.setBaseRedemptionFee(1e16);

        vm.expectRevert("!core");
        redemptionHandler.setDiscountInfo(1e17, 3e17, 5e14);

        vm.expectRevert("!core");
        redemptionHandler.setUnderlyingOracle(address(0x123));
    }

    function test_InvalidFeeSettings() public {
        vm.startPrank(address(core));
        vm.expectRevert("fee too high");
        redemptionHandler.setBaseRedemptionFee(2e18);
        vm.expectRevert("max discount exceeds base redemption fee");
        redemptionHandler.setDiscountInfo(
            1e17, // rate
            3e17, // max usage
            2e16  // max discount
        );
        vm.stopPrank();
    }

    function test_GetRedemptionFeePct() public {
        uint256 feePct = redemptionHandler.getRedemptionFeePct(address(testPair), 10_000e18);
        assertGt(feePct, 0, "Fee should be greater than 0");
        assertLe(feePct, 1e18, "Fee should not exceed 100%");
    }

    function test_PreviewRedeem() public {
        uint256 redeemAmount = 1000e18;
        (
            uint256 returnedUnderlying, 
            uint256 returnedCollateral, 
            uint256 fee
        ) = redemptionHandler.previewRedeem(address(testPair), redeemAmount);
        assertGt(fee, 0, "Fee should be greater than 0");
        assertLe(fee, 1e18, "Fee should not exceed 100%");
    }
}
