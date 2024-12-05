
// import { console } from "forge-std/console.sol";
import { console } from "lib/forge-std/src/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { Vm } from "forge-std/Vm.sol";
import { RedemptionFeeCalculator } from "src/protocol/RedemptionFeeCalculator.sol";
import { PairTestBase } from "./PairTestBase.t.sol";


contract PairTest is PairTestBase {
    RedemptionFeeCalculator public redemptionFeeCalculator;

    function setUp() public override {
        super.setUp();
        deal(address(pair.collateral()), address(this), 100_000_000e18);
        deal(address(address(stablecoin)), address(this), 100_000_000e18);
        addCollateral(pair, 100_000_000e18);
        collateral.approve(address(pair), type(uint256).max);
        stablecoin.approve(address(redemptionHandler), type(uint256).max);
        redemptionFeeCalculator = new RedemptionFeeCalculator(address(core), address(redemptionHandler));
        vm.startPrank(address(core));
        pair.setBorrowLimit(type(uint128).max);
        redemptionHandler.setRedemptionFeeCalculator(address(redemptionFeeCalculator));
        vm.stopPrank();
    }

    function test_getRedemptionFee() public {
        uint256 borrowAmount = 100_000e18;
        uint256 redemptionAmount = borrowAmount / 100;
        for (uint256 i = 0; i < 10; i++) {
            borrow(
                pair, 
                borrowAmount,   // borrow amount
                0                   // no collateral
            );

            uint256 fee = redemptionFeeCalculator.getRedemptionFeeWithDecay(
                address(pair), 
                redemptionAmount
            );

            redemptionHandler.redeemFromPair(
                address(pair), 
                redemptionAmount, 
                1e18, // max fee pct
                address(this), 
                true
            );
            (uint256 amt, ) = pair.totalBorrow();
            console.log(i, 'Fee: ', fee, amt);
        }
    }
}