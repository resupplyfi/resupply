// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PairTestBase } from "./PairTestBase.t.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { ResupplyPairConstants } from "src/protocol/pair/ResupplyPairConstants.sol";
import { console } from "forge-std/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { MockOracle } from "test/mocks/MockOracle.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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

        depositToInsurancePool(1_000_000e18);
    }

    
    function test_LiquidateBasic() public {
        buildLiquidatablePosition();

        uint256 ipStableBalance = stablecoin.balanceOf(address(insurancePool));
        uint256 ipUnderlyingBalance = underlying.balanceOf(address(insurancePool));
        uint256 ipTotalSupply = insurancePool.totalSupply();
        uint256 ipTotalAssets = insurancePool.totalAssets();
        uint256 pairCollateralBalance = collateral.balanceOf(address(pair));


        vm.expectEmit(true, false, false, false, address(liquidationHandler));
        emit LiquidationHandler.CollateralProccessed(address(collateral), 0, 0);
        liquidationHandler.liquidate(address(pair), address(this));

        assertEq(collateral.balanceOf(address(liquidationHandler)), 0);
        assertEq(underlying.balanceOf(address(liquidationHandler)), 0);
        assertLt(stablecoin.balanceOf(address(insurancePool)), ipStableBalance, 'stablecoin balance should decrease');
        assertGt(underlying.balanceOf(address(insurancePool)), ipUnderlyingBalance, 'underlying balance should increase');
        assertEq(insurancePool.totalSupply(), ipTotalSupply, 'total supply should not change');
        assertLt(insurancePool.totalAssets(), ipTotalAssets, 'total assets should decrease');
        assertLt(collateral.balanceOf(address(pair)), pairCollateralBalance, 'pair collateral balance should decrease');
    }

    function test_LiquidateSolventBorrowerFails() public {
        uint256 amount = 1000e18;
        borrow(pair, amount, calculateMinUnderlyingNeededForBorrow(amount)); 

        vm.expectRevert(ResupplyPairConstants.BorrowerSolvent.selector);
        liquidationHandler.liquidate(address(pair), address(this));
    }

    function test_LiquidationCollateralArrivesInIP() public {
        buildLiquidatablePosition();
        liquidationHandler.liquidate(address(pair), address(this));

    }

    function test_LiquidationWithIlliquidCollateral() public {
        buildLiquidatablePosition();
        withdrawLiquidityFromMarket();

        uint256 ipUnderlyingBalance = underlying.balanceOf(address(insurancePool));
        liquidationHandler.liquidate(address(pair), address(this));
        assertGt(collateral.balanceOf(address(liquidationHandler)), 0, 'liquidationHandler collateral balance should be greater than 0');
        assertEq(underlying.balanceOf(address(insurancePool)), 0, 'IP underlying balance should be 0');

        resupplyLiquidityToMarket();

        ipUnderlyingBalance = underlying.balanceOf(address(insurancePool));
        
        // We should be able to process collateral now
        liquidationHandler.processCollateral(address(collateral));
        assertEq(collateral.balanceOf(address(liquidationHandler)), 0, 'liquidationHandler collateral balance should be 0');
        assertGt(underlying.balanceOf(address(insurancePool)), ipUnderlyingBalance, 'IP underlying balance should increase');
    }

    function test_migrateCollateral() public {
        LiquidationHandler newLiquidationHandler = new LiquidationHandler(
            address(core),
            address(registry),
            address(insurancePool)
        );
        uint256 amt = 100_000e18;
        deal(address(collateral), address(liquidationHandler), amt);
        vm.startPrank(address(core));
        vm.expectRevert("handler still used");
        liquidationHandler.migrateCollateral(address(collateral), amt, address(newLiquidationHandler));

        registry.setLiquidationHandler(address(newLiquidationHandler));
        liquidationHandler.migrateCollateral(address(collateral), collateral.balanceOf(address(liquidationHandler)), address(newLiquidationHandler));
        vm.stopPrank();
        assertEq(collateral.balanceOf(address(newLiquidationHandler)), amt);
    }

    function test_distributeCollateralAndClearDebt() public {
        buildLiquidatablePosition();
        withdrawLiquidityFromMarket(); // do this to simulate a market w bad debt.

        uint256 ipStableBalance = stablecoin.balanceOf(address(insurancePool));
        uint256 ipUnderlyingBalance = underlying.balanceOf(address(insurancePool));
        uint256 ipTotalSupply = insurancePool.totalSupply();
        uint256 ipTotalAssets = insurancePool.totalAssets();
        uint256 pairCollateralBalance = collateral.balanceOf(address(pair));
        uint256 ipCollateralBalance = collateral.balanceOf(address(insurancePool));

        vm.startPrank(address(core));
        insurancePool.addExtraReward(address(collateral));
        pair.setMaxLTV(1);
        pair.setBorrowLimit(0);
        liquidationHandler.liquidate(address(pair), address(this));

        liquidationHandler.distributeCollateralAndClearDebt(address(collateral));

        assertEq(collateral.balanceOf(address(liquidationHandler)), 0, 'liquidationHandler collateral balance should be 0');
        assertEq(underlying.balanceOf(address(liquidationHandler)), 0, 'liquidationHandler underlying balance should be 0');
        assertLt(stablecoin.balanceOf(address(insurancePool)), ipStableBalance, 'stablecoin balance should decrease');
        assertEq(underlying.balanceOf(address(insurancePool)), ipUnderlyingBalance, 'underlying balance should not change');
        assertEq(insurancePool.totalSupply(), ipTotalSupply, 'total supply should not change');
        assertLt(insurancePool.totalAssets(), ipTotalAssets, 'total assets should decrease');
        assertLt(collateral.balanceOf(address(pair)), pairCollateralBalance, 'pair collateral balance should decrease');
        assertGt(collateral.balanceOf(address(insurancePool)), ipCollateralBalance, 'IP collateral balance should increase');
        vm.stopPrank();
    }

    function resetOraclePriceToNormal() public {
        mockOracle.setPrice(0);
        pair.updateExchangeRate();
    }

    function setOraclePrice(uint256 _price) public {
        mockOracle.setPrice(_price);
        skip(1); // Must skip to new timestamp to update oracle
        pair.updateExchangeRate();
    }

    function depositToInsurancePool(uint256 _amount) public {
        deal(address(stablecoin), address(this), _amount);
        insurancePool.deposit(_amount, address(this));
    }

    function buildLiquidatablePosition() public {
        uint256 borrowAmount = pair.minimumBorrowAmount();
        borrow(pair, borrowAmount, calculateMinUnderlyingNeededForBorrow(borrowAmount)); // borrow while adding collateral
        setOraclePrice(1e17);
    }

    function withdrawLiquidityFromMarket() public {
        deal(address(collateral), user1, collateral.totalSupply() * 10000);
        IERC4626 _collateral = IERC4626(address(collateral));
        uint256 toRedeem = _collateral.maxRedeem(user1);
        vm.startPrank(user1);
        _collateral.redeem(toRedeem, user1, user1);
        vm.stopPrank();
    }

    function resupplyLiquidityToMarket() public {
        IERC4626 _collateral = IERC4626(address(collateral));
        uint256 toSupply = underlying.balanceOf(user1);

        vm.startPrank(user1);
        underlying.approve(address(collateral), type(uint256).max);
        _collateral.deposit(toSupply, address(this));
        vm.stopPrank();
    }
}
