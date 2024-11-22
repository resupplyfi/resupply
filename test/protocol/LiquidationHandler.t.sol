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
        vm.prank(address(core));
        pair.setOracle(address(mockOracle));

        // LH
        require(registry.liquidationHandler() == address(liquidationHandler), "!liq handler");
        require(registry.insurancePool() == address(insurancePool), "IP not setup in registry");
        require(liquidationHandler.insurancePool() == address(insurancePool), "IP not setup in LH");

        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);
        stablecoin.approve(address(liquidationHandler), type(uint256).max);
        stablecoin.approve(address(insurancePool), type(uint256).max);

        deal(address(stablecoin), address(this), 10_000e18);
        depositToInsurancePool(10_000e18);
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
        console.log('LTV1', getCurrentLTV(pair, address(this)));
        skip(1000 days);
        console.log('LTV2', getCurrentLTV(pair, address(this)));
        mockOracle.setPrice(1e18);
        pair.updateExchangeRate();
        console.log('LTV3', getCurrentLTV(pair, address(this)));
        liquidationHandler.liquidate(address(pair), address(this));
    }

    // function test_LiquidateFails() public {
    //     uint256 amount = 1000e18;
    //     deal(address(collateral), address(this), amount);
    //     borrow(pair, amount, amount); 

    //     vm.expectRevert(ResupplyPairConstants.BorrowerSolvent.selector);
    //     liquidationHandler.liquidate(address(pair), address(this));
    // }

    function test_LiquidationCollateralArrivesInIP() public {
        // TODO: Make sure rewards are flowing
    }

    function resetOraclePriceToNormal() public {
        mockOracle.setPrice(0);
        pair.updateExchangeRate();
    }

    function reduceOraclePrice(uint256 _price) public {
        mockOracle.setPrice(_price);
        pair.updateExchangeRate();
    }

    function depositToInsurancePool(uint256 _amount) public {
        insurancePool.deposit(_amount, address(this));
    }
}
