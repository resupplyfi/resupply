// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "test/helpers/FraxPairInvariants.sol";

abstract contract SDolaForkTests is ForkTests {
    function test_borrowDisallowedOnUSDeDepeg() public {
        testForkDepositUnderlyingToPair();
        testForkSupplyToLendingPair();

        _nukeSDolaPool_sellDola();

        vm.startPrank(alice);
        uint256 maxLtv = fraxlendPair.maxLTV();
        fraxlendPair.updateExchangeRate();
        (, , , uint256 low, uint256 high) = fraxlendPair.exchangeRateInfo();
        uint256 borrowAmt = (ONE_COLLATERAL * ((maxLtv * 1e18) / LTV_PRECISION)) / high;

        vm.expectRevert(FraxlendPairConstants.ExceedsMaxOracleDeviation.selector);
        fraxlendPair.borrowAsset(borrowAmt, 0, alice);
    }

    function test_borrowFineOnFraxDepeg() public {
        testForkDepositUnderlyingToPair();
        testForkSupplyToLendingPair();

        _nukeSDolaPool_sellFrax();

        vm.startPrank(alice);
        uint256 maxLtv = fraxlendPair.maxLTV();
        fraxlendPair.updateExchangeRate();
        (, , , uint256 low, uint256 high) = fraxlendPair.exchangeRateInfo();
        uint256 borrowAmt = (ONE_COLLATERAL * ((maxLtv * 1e18) / LTV_PRECISION)) / high;

        assertEq(high, low);
        _assertExpectedPriceDepegUpward(low);
        fraxlendPair.borrowAsset(borrowAmt, 0, alice);
    }

    function _assertExpectedPriceDepegUpward(uint256 _lowPrice) internal virtual {}

    function test_liquidationsWorkOnUSDeDepeg() public {
        testForkBorrowingPowerInvariant();

        _nukeSDolaPool_sellDola();

        vm.warp(block.timestamp + 10_000 days);
        fraxlendPair.updateExchangeRate();
        deal(address(asset), liquidator, 2_000_000e18);

        (, , , uint256 low, uint256 high) = fraxlendPair.exchangeRateInfo();
        uint256 sharesToLiquidate = fraxlendPair.userBorrowShares(alice) / 20;

        vm.startPrank(liquidator);
        asset.approve(address(fraxlendPair), 2_000_000e18);
        fraxlendPair.liquidate(uint128(sharesToLiquidate), block.timestamp + 100, alice);

        uint256 amtSpent = stdMath.delta(asset.balanceOf(liquidator), 2_000_000e18);
        uint256 amtToLiquidate = fraxlendPair.toBorrowAmount(sharesToLiquidate, false, false);

        console.log("(amtSpent, amtToLiquidate): ", amtSpent, amtToLiquidate);
        uint256 amtSpot = (amtToLiquidate * low) / 1e18;
        console.log("The low: ", low);
        console.log("amtSpot --->", amtSpot, fraxlendPair.dirtyLiquidationFee());
        uint256 amtSpotDirty = ((1e5 + fraxlendPair.dirtyLiquidationFee()) * amtSpot) / 1e5;
        console.log("--->", amtSpotDirty);
        uint256 protocolFees = ((fraxlendPair.protocolLiquidationFee()) * amtSpotDirty) / 1e5;
        console.log("       ---> The protocol liquidation fees: ", protocolFees);
        uint256 liqPayment = stdMath.delta(protocolFees, amtSpotDirty);

        // Assert that the liquidator receives the calculated payment
        assertEq(liqPayment, collateral.balanceOf(liquidator));
        console.log("The payment for liquidation: ", liqPayment);
        console.log("The premium for the liquidator: ", liqPayment - amtSpot);

        // Assert that the collateralSeized is w/n 1 wei of the value calculated (Diff due to rounding)
        uint256 collateralSeized = stdMath.delta(fraxlendPair.userCollateralBalance(alice), ONE_COLLATERAL);
        uint256 diff = stdMath.delta(collateralSeized, amtSpotDirty);
        assertLe(diff, 1, "Collateral Seized amount off");
        assertEq(collateralSeized, amtSpotDirty);
    }

    function _nukeSDolaPool_sellDola() internal {
        address whale = address(0xBEEF);
        ICurve pool = ICurve(0xef484de8C07B6e2d732A92B5F78e81B38f99f95E);
        deal(Constants.Mainnet.DOLA_ERC20, whale, 10_000_000e18);

        vm.startPrank(whale);
        IERC20(Constants.Mainnet.DOLA_ERC20).approve(address(pool), 10_000_000e18);
        pool.exchange_underlying(0, 2, 10_000_000e18, 0);
        vm.warp(block.timestamp + 1 days);
    }

    function _nukeSDolaPool_sellFrax() internal {
        address whale = address(0xBEEF);
        ICurve pool = ICurve(0xef484de8C07B6e2d732A92B5F78e81B38f99f95E);
        deal(Constants.Mainnet.FRAX_ERC20, whale, 10_000_000e18);

        vm.startPrank(whale);
        IERC20(Constants.Mainnet.FRAX_ERC20).approve(address(pool), 10_000_000e18);
        pool.exchange_underlying(1, 0, 10_000_000e18, 0);
        vm.warp(block.timestamp + 1 days);
    }
}

interface ICurve {
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_day) external;

    function exchange_underlying(int128 i, int128 j, uint256 _dx, uint256 _min_day) external;

    function price_oracle(uint256) external view returns (uint256);
}
