// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;
import { console } from "lib/forge-std/src/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { Setup } from "test/Setup.sol";
import { PairTestBase } from "./PairTestBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ResupplyPairConstants } from "src/protocol/pair/ResupplyPairConstants.sol";
import { Vm } from "forge-std/Vm.sol";

contract PairTest is PairTestBase {
    function setUp() public override {
        super.setUp();
        stablecoin.approve(address(redemptionHandler), type(uint256).max);
    }

    function test_AddCollateral() public {
        assertEq(pair.userCollateralBalance(_THIS), 0);

        uint256 amount = 100e18;
        deal(address(collateral), address(this), amount);

        pair.addCollateralVault(amount, address(this));

        assertEq(pair.userCollateralBalance(_THIS), amount);
    }

    function test_AddCollateralUnderlying() public {
        assertEq(pair.userCollateralBalance(_THIS), 0);
        
        uint256 amount = 100e18;
        deal(address(underlying), address(this), amount);

        pair.addCollateral(amount, address(this));
        uint256 shares = IERC4626(address(collateral)).convertToShares(amount);

        assertEq(pair.userCollateralBalance(_THIS), shares);
    }

    function test_RemoveCollateral() public {
        addCollateral(pair, 100_000e18);
        uint256 shares = pair.userCollateralBalance(_THIS);
        uint256 startBalance = collateral.balanceOf(address(this));
        // Make sure we get out
        pair.removeCollateralVault(shares, address(this));
        assertEq(collateral.balanceOf(address(this)), startBalance + shares);
    }

    function test_RemoveCollateralUnderlying() public {
        addCollateral(pair, 100_000e18);
        uint256 shares = pair.userCollateralBalance(_THIS);
        uint256 amount = convertToAssets(address(collateral), shares);
        uint256 startBalance = underlying.balanceOf(address(this));
        pair.removeCollateral(shares, address(this));
        assertEq(underlying.balanceOf(address(this)), startBalance + amount);
    }

    function test_Borrow() public {
        uint256 collateralAmount = 106_000e18;
        uint256 borrowAmount = 100_000e18;

        addCollateral(pair, convertToShares(address(collateral), collateralAmount));
        borrow(pair, borrowAmount, 0);
    }

    function test_RedemptionPartial() public {
        uint256 collateralAmount = 1_500_000e18;
        uint256 borrowAmount = 500_000e18;
        uint256 redeemAmount = 10_000e18;

        console.log("redemption token: ", address(pair.redemptionWriteOff()));

        (address reward0, bool isclaimable, uint256 rewardsRemaining) = pair.rewards(0);
        console.log("reward0 token", reward0);
        console.log("reward0 isclaimable", isclaimable);
        console.log("reward0 rewardsRemaining", uint(rewardsRemaining));
        console.logUint(rewardsRemaining);


        addCollateral(pair, convertToShares(address(collateral), collateralAmount));
        borrow(pair, borrowAmount, 0);

        // deal(address(stablecoin), address(this), redeemAmount);
        deal(address(stablecoin), address(this), borrowAmount);
        
        vm.expectRevert("fee > maxFee");
        redemptionHandler.redeemFromPair(
            address(pair),  // pair
            redeemAmount,   // amount
            0,              // max fee
            address(this),  // return to
            false           // unwrap
        );

        

        uint256 underlyingBalBefore = underlying.balanceOf(address(this));
        uint256 stablecoinBalBefore = stablecoin.balanceOf(address(this));
        uint256 collateralBalBefore = pair.userCollateralBalance(address(this));
        (uint256 totalDebtBefore, ) = pair.totalBorrow();
        uint256 otherFeesBefore = pair.claimableOtherFees();
        uint256 totalFee = redemptionHandler.getRedemptionFeePct(address(pair), redeemAmount);
        uint256 nextFee = redemptionHandler.getRedemptionFeePct(address(pair), 1);

        uint256 crvusdprice = underlyingoracle.getPrices(Constants.Mainnet.CURVE_USD_ERC20);
        uint256 gascost = vm.snapshotGasLastCall("curvePriceGas");
        console.log("curve price gas: ", gascost);
        console.log("crvusd price: ", crvusdprice);

        // underlyingoracle.getAggPrice();
        // gascost = vm.snapshotGasLastCall("curvePriceGasAgg");
        // console.log("curve agg price gas: ", gascost);

        // underlyingoracle.getAggPriceWrite();
        // gascost = vm.snapshotGasLastCall("curvePriceGasAggWrite");
        // console.log("curve agg write price gas: ", gascost);
        uint256 frxusdprice = underlyingoracle.getPrices(address(0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29));
        gascost = vm.snapshotGasLastCall("fraxPriceGas");
        console.log("frxusd price gas: ", gascost);
        console.log("frxusdprice price: ", frxusdprice);

        console.log("underlying oracle: ", redemptionHandler.underlyingOracle());

        (uint256 previewUnderlying, uint256 previewCollateral, uint256 previewFee) = redemptionHandler.previewRedeem(address(pair),redeemAmount);
        bool useUnwrap = true;
        uint256 returnedTokenAmount = redemptionHandler.redeemFromPair(
            address(pair),  // pair
            redeemAmount,   // amount
            1e18,           // max fee
            address(this),  // return to
            useUnwrap           // unwrap
        );

        uint256 underlyingBalAfter = underlying.balanceOf(address(this));
        uint256 underlyingGain = underlyingBalAfter - underlyingBalBefore;
        uint256 collateralBalAfter = pair.userCollateralBalance(address(this));
        assertGt(underlyingGain, 0);
        assertEq(stablecoinBalBefore - stablecoin.balanceOf(address(this)), redeemAmount);
        uint256 feesPaid = redeemAmount - underlyingGain;
        assertGt(feesPaid, 0);
        if(useUnwrap){
            assertEq(returnedTokenAmount, underlyingGain);
        }else{
            assertEq(returnedTokenAmount, previewCollateral);
        }
        assertEq(underlyingGain, previewUnderlying);
        

        (uint256 totalDebtAfter, ) = pair.totalBorrow();
        uint256 debtWrittenOff = totalDebtBefore - totalDebtAfter;
        uint256 amountToStakers = pair.claimableOtherFees() - otherFeesBefore;
        console.log("previewUnderlying", previewUnderlying);
        console.log("previewCollateral", previewCollateral);
        console.log("previewFee", previewFee);
        console.log("nextFee", nextFee);
        console.log("real fee", totalFee);
        console.log("redeemAmount", redeemAmount);
        console.log("returnedTokenAmount", returnedTokenAmount);
        console.log("collateralBefore", collateralBalBefore);
        console.log("collateralAfter", collateralBalAfter);
        console.log("debtWrittenOff", debtWrittenOff);
        console.log("underlyingReturned", underlyingGain);
        console.log("feesPaid (w/ rounding error)", feesPaid);
        console.log("amountToStakers", amountToStakers);
        printEarned(pair, address(this));

        (,uint192 pairUsage) = redemptionHandler.ratingData(address(pair));
        console.log("current pair usage: ", pairUsage);
        console.log("continue redemptions...");
        for(uint256 i=0; i < 5; i++){
            totalFee = redemptionHandler.getRedemptionFeePct(address(pair), redeemAmount);
            collateralBalAfter = pair.userCollateralBalance(address(this));
            redemptionHandler.redeemFromPair(
                address(pair),  // pair
                redeemAmount,   // amount
                1e18,           // max fee
                address(this),  // return to
                true           // unwrap
            );
            console.log("fee used: ", totalFee);
            nextFee = redemptionHandler.getRedemptionFeePct(address(pair), 1);
            console.log("nextFee: ", nextFee);
            (, pairUsage) = redemptionHandler.ratingData(address(pair));
            console.log("current pair usage: ", pairUsage);
            console.log("collateral remaining: ", collateralBalAfter);
        }

        uint256 minimumRedeem = pair.minimumRedemption();
        for(uint256 i=0; i < 20; i++){
            vm.warp(block.timestamp +7 days);
            console.log("warp forward...");
            nextFee = redemptionHandler.getRedemptionFeePct(address(pair), 1);
            console.log("nextFee: ", nextFee);
            redemptionHandler.redeemFromPair(
                address(pair),  // pair
                minimumRedeem,   // amount
                1e18,           // max fee
                address(this),  // return to
                true           // unwrap
            );
            (, pairUsage) = redemptionHandler.ratingData(address(pair));
            console.log("current pair usage: ", pairUsage);
        }
        

        assertZeroBalanceRH();
    }

    function test_RedemptionMax() public {
        uint256 collateralAmount = 150_000e18;
        uint256 borrowAmount = 100_000e18;
        uint256 redeemAmount = redemptionHandler.getMaxRedeemableDebt(address(pair));
        addCollateral(pair, convertToShares(address(collateral), collateralAmount));
        borrow(pair, borrowAmount, 0);

        (uint256 totalDebtBefore, ) = pair.totalBorrow();

        redeemAmount = redemptionHandler.getMaxRedeemableDebt(address(pair));
        deal(address(stablecoin), address(this), redeemAmount);
        uint256 underlyingBalBefore = underlying.balanceOf(address(this));
        uint256 otherFeesBefore = pair.claimableOtherFees();
        uint256 totalFee = redemptionHandler.getRedemptionFeePct(address(pair), redeemAmount);
        uint256 stablecoinBalBefore = stablecoin.balanceOf(address(this));
        
        // We expect this to revert because the total remaining debt is less than `minimumLeftoverDebt`
        vm.expectRevert(ResupplyPairConstants.InsufficientDebtToRedeem.selector);
        uint256 collateralFreed = redemptionHandler.redeemFromPair(
            address(pair),  // pair
            redeemAmount + uint256(500e18), // add some to force revert
            1e18,           // max fee
            address(this),  // return to
            true            // unwrap
        );
        
        console.log("totalDebtBefore", totalDebtBefore);
        console.log("redeemAmount", redeemAmount);
        collateralFreed = redemptionHandler.redeemFromPair(
            address(pair),  // pair
            redeemAmount,   // amount
            1e18,           // max fee
            address(this),  // return to
            true           // unwrap
        );
        assertGt(collateralFreed, 0);
        (,,uint256 exchangeRate) = pair.exchangeRateInfo();
        uint256 underlyingBalAfter = underlying.balanceOf(address(this));
        uint256 underlyingGain = underlyingBalAfter - underlyingBalBefore;
        assertGt(underlyingGain, 0);
        assertEq(stablecoinBalBefore - stablecoin.balanceOf(address(this)), redeemAmount);
        uint256 feesPaid = redeemAmount - underlyingGain;
        assertGt(feesPaid, 0);
        

        (uint256 totalDebtAfter, ) = pair.totalBorrow();
        uint256 debtWrittenOff = totalDebtBefore - totalDebtAfter;
        uint256 amountToStakers = pair.claimableOtherFees() - otherFeesBefore;
        console.log("totalFeePct", totalFee);
        console.log("redeemAmount", redeemAmount);
        console.log("collateralFreed", collateralFreed);
        console.log("debtWrittenOff", debtWrittenOff);
        console.log("underlyingReturned", underlyingGain);
        console.log("feesPaid (w/ rounding error)", feesPaid);
        console.log("amountToStakers", amountToStakers);


        assertZeroBalanceRH();
    }

    function test_RedemptionFeesClaimable() public {
        uint256 collateralAmount = 150_000e18;
        uint256 borrowAmount = 100_000e18;

        addCollateral(pair, convertToShares(address(collateral), collateralAmount));
        borrow(pair, borrowAmount, 0);

        uint256 redeemAmount = 10_000e18;
        deal(address(stablecoin), address(this), redeemAmount);

        assertEq(pair.claimableOtherFees(), 0);
        
        redemptionHandler.redeemFromPair(
            address(pair),  // pair
            redeemAmount,   // amount
            1e18,           // max fee
            address(this),  // return to
            true           // unwrap
        );
        uint256 claimableFees = pair.claimableOtherFees();
        assertGt(claimableFees, 0);

        vm.expectRevert(ResupplyPair.FeesAlreadyDistributed.selector);
        (uint256 fees, uint256 otherFees) = pair.withdrawFees();
        uint256 currentEpoch = pair.getEpoch();

        skip(epochLength);
        assertGt(pair.getEpoch(), currentEpoch);
        
        vm.prank(address(feeDepositController));
        feeDeposit.distributeFees();
        
        
        vm.expectEmit(true, false, false, false); // False to not check topics 2/3 or data
        emit ResupplyPair.WithdrawFees(
            registry.feeDeposit(), // recipient
            pair.claimableFees(),   // fees
            pair.claimableOtherFees() // otherFees
        );
        (fees, otherFees) = pair.withdrawFees();
        assertEq(pair.claimableOtherFees(), 0);
        assertGt(otherFees, 0);
        assertZeroBalanceRH();
    }

    function assertZeroBalanceRH() internal {
        assertEq(collateral.balanceOf(address(redemptionHandler)), 0);
        assertEq(underlying.balanceOf(address(redemptionHandler)), 0);
        assertEq(stablecoin.balanceOf(address(redemptionHandler)), 0);
    }

    function test_Pause() public {
        uint256 amount = 100_000e18;
        deal(address(underlying), address(this), amount);
        addCollateral(pair, amount);
        underlying.approve(address(pair), type(uint256).max);
        uint256 borrowAmount = 10_000e18;
        uint256 startLimit = pair.borrowLimit();
        assertGt(startLimit, 0);
        vm.startPrank(pair.owner());
        pair.unpause();
        assertGt(pair.borrowLimit(), 0); // ensure unpausing doesn't set to 0
        pair.pause();
        vm.stopPrank();
        assertEq(pair.borrowLimit(), 0);
        vm.expectRevert(
            abi.encodeWithSelector(ResupplyPairConstants.InsufficientDebtAvailable.selector, 0, borrowAmount)
        );
        pair.borrow(borrowAmount, 20_000e18, address(this));
        // ensure double pause does not set previous to 0.
        vm.startPrank(pair.owner());
        pair.pause();
        pair.unpause();
        assertEq(pair.borrowLimit(), startLimit);
        vm.stopPrank();
    }

}
