import { console } from "forge-std/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { Setup } from "test/Setup.sol";
import { PairTestBase } from "./PairTestBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract PairTest is PairTestBase {
    ResupplyPair pair;
    IERC20 collateral;
    IERC20 underlying;

    function setUp() public override {
        super.setUp();

        deployDefaultLendingPairs();
        address[] memory _pairs = registry.getAllPairAddresses();
        pair = ResupplyPair(_pairs[0]); 
        collateral = pair.collateral();
        underlying = pair.underlying();
        printPairInfo(pair);

        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);
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

    function test_Redemption() public {
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

        uint256 balBefore = underlying.balanceOf(address(this));
        (uint256 totalDebtBefore, ) = pair.totalBorrow();
        redemptionHandler.redeemFromPair(
            address(pair),  // pair
            redeemAmount,   // amount
            1e18,           // max fee
            address(this),  // return to
            true           // unwrap
        );
        uint256 balAfter = underlying.balanceOf(address(this));
        uint256 underlyingGain = balAfter - balBefore;
        assertGt(underlyingGain, 0);
        uint256 feesPaid = redeemAmount - underlyingGain;
        assertGt(feesPaid, 0);
        console.log("redeemAmount", redeemAmount);
        console.log("underlyingGain", underlyingGain);
        console.log("feesPaid (w/ rounding error)", feesPaid);

        (uint256 totalDebtAfter, ) = pair.totalBorrow();
        uint256 debtWrittenOff = totalDebtBefore - totalDebtAfter;
        uint256 amountToStakers = pair.claimableFees() + pair.claimableOtherFees();
        console.log("debtWrittenOff", debtWrittenOff);
        console.log("amountToStakers", amountToStakers);
    }
}
