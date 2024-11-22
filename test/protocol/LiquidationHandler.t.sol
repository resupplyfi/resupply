import { PairTestBase } from "./PairTestBase.t.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { ResupplyPairConstants } from "src/protocol/pair/ResupplyPairConstants.sol";
import { console } from "forge-std/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { MockOracle } from "test/mocks/MockOracle.sol";

contract LiquidationManagerTest is PairTestBase {

    MockOracle mockOracle;

    function setUp() public override {
        super.setUp();

        mockOracle = new MockOracle("Mock Oracle", 1e18);

        mockOracle.setPrice(1e18);

        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);
        stablecoin.approve(address(liquidationHandler), type(uint256).max);
    }

    function test_LiquidateBasic() public {
        uint256 amount = 1000e18;
        uint256 maxBorrow = (
            convertToAssets(address(collateral), amount) *
            pair.maxLTV() /
            ResupplyPairConstants.LTV_PRECISION
        );
        console.log('maxBorrow', maxBorrow);
        console.log('maxLTV', pair.maxLTV());
        console.log('convertToAssets', convertToAssets(address(collateral), amount));
        deal(address(collateral), address(this), amount);
        borrow(pair, maxBorrow - 1e18, amount); // borrow while adding collateral
        uint256 ltv = getCurrentLTV(pair, address(this));
        console.log('LTV1', ltv);
        skip(1000 days);
        ltv = getCurrentLTV(pair, address(this));
        console.log('LTV2', ltv);
        liquidationHandler.liquidate(address(pair), address(this));
    }

    function test_LiquidateFails() public {
        uint256 amount = 1000e18;
        deal(address(collateral), address(this), amount);
        borrow(pair, amount, amount); 

        vm.expectRevert(ResupplyPairConstants.BorrowerSolvent.selector);
        liquidationHandler.liquidate(address(pair), address(this));
    }
}