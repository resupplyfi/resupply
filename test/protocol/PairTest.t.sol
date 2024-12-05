import { console } from "forge-std/console.sol";
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
        stablecoin.approve(address(pair), type(uint256).max);
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
        uint256 collateralAmount = 150_000e18;
        uint256 borrowAmount = 100_000e18;
        uint256 redeemAmount = 10_000e18;

        addCollateral(pair, convertToShares(address(collateral), collateralAmount));
        borrow(pair, borrowAmount, 0);

        deal(address(stablecoin), address(this), redeemAmount);
        
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
        (uint256 totalDebtBefore, ) = pair.totalBorrow();
        uint256 otherFeesBefore = pair.claimableOtherFees();
        uint256 totalFee = redemptionHandler.getRedemptionFeeWithDecay(address(pair), redeemAmount);
        uint256 collateralFreed = redemptionHandler.redeemFromPair(
            address(pair),  // pair
            redeemAmount,   // amount
            1e18,           // max fee
            address(this),  // return to
            true           // unwrap
        );
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

    function test_RedemptionMax() public {
        uint256 collateralAmount = 150_000e18;
        uint256 borrowAmount = 100_000e18;
        uint256 redeemAmount = redemptionHandler.getMaxRedeemableValue(address(pair));
        addCollateral(pair, convertToShares(address(collateral), collateralAmount));
        borrow(pair, borrowAmount, 0);

        (uint256 totalDebtBefore, ) = pair.totalBorrow();

        redeemAmount = redemptionHandler.getMaxRedeemableValue(address(pair));
        deal(address(stablecoin), address(this), redeemAmount);
        uint256 underlyingBalBefore = underlying.balanceOf(address(this));
        uint256 otherFeesBefore = pair.claimableOtherFees();
        uint256 totalFee = redemptionHandler.getRedemptionFeeWithDecay(address(pair), redeemAmount);
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

    function test_Pause() public {
        assertGt(pair.borrowLimit(), 0);
        assertEq(pair.paused(), false);
        uint256 initialBorrowLimit = pair.borrowLimit();

        vm.expectRevert("!core");
        pair.pause();
        assertEq(pair.paused(), false);

        vm.startPrank(address(core));

        pair.pause();
        assertTrue(pair.paused());
        assertEq(pair.borrowLimit(), 0);

        vm.expectRevert("paused");
        pair.setBorrowLimit(100e18);

        vm.stopPrank();

        vm.expectRevert("!core");
        pair.unpause();

        vm.startPrank(address(core));
        pair.unpause();
        assertEq(pair.borrowLimit(), initialBorrowLimit);
        assertEq(pair.paused(), false);
    }

    function assertZeroBalanceRH() internal {
        assertEq(collateral.balanceOf(address(redemptionHandler)), 0);
        assertEq(underlying.balanceOf(address(redemptionHandler)), 0);
        assertEq(stablecoin.balanceOf(address(redemptionHandler)), 0);
    }

}
