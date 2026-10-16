// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PairTestBase } from "./PairTestBase.t.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { console } from "lib/forge-std/src/console.sol";
import { MockOracle } from "test/mocks/MockOracle.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IResupplyPairErrors } from "src/protocol/pair/IResupplyPairErrors.sol";

contract LiquidationHandlerTest is PairTestBase {

    uint256 internal constant TEST_BPS = 10_000;
    uint256 internal constant FULL_FEE_COLLATERAL_RATIO_BPS = 10_510;
    uint256 internal constant PARTIAL_FEE_COLLATERAL_RATIO_BPS = 10_200;
    uint256 internal constant BAD_DEBT_COLLATERAL_RATIO_BPS = 9_900;

    struct IncentivePreview {
        uint256 seizedShares;
        uint256 userCollateralShares;
        uint256 feeShares;
        uint256 nominalFeeShares;
        uint256 rawRewardShares;
        uint256 maxRewardShares;
        uint256 rewardShares;
        uint256 rewardAssets;
    }

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

        vm.prank(pair.owner());
        pair.setBorrowLimit(5_000_000e18);
    }

    
    function test_LiquidateBasic() public {
        buildLiquidatablePosition();

        uint256 ipStableBalance = stablecoin.balanceOf(address(insurancePool));
        uint256 ipUnderlyingBalance = underlying.balanceOf(address(insurancePool));
        uint256 ipTotalSupply = insurancePool.totalSupply();
        uint256 ipTotalAssets = insurancePool.totalAssets();
        uint256 pairCollateralBalance = pair.totalCollateral();

        printPairInfo(pair);
        printUserInfo(pair, address(this));
        vm.prank(address(core));
        pair.setMaxLTV(1);

        vm.expectEmit(true, false, false, false, address(liquidationHandler));
        emit LiquidationHandler.CollateralProccessed(address(collateral), 0, 0);
        liquidationHandler.liquidate(address(pair), address(this));
        uint256 gascost = vm.snapshotGasLastCall("Liquidate");
        console.log("liquidate gas: ", gascost);

        assertEq(collateral.balanceOf(address(liquidationHandler)), 0);
        assertEq(underlying.balanceOf(address(liquidationHandler)), 0);
        assertLt(stablecoin.balanceOf(address(insurancePool)), ipStableBalance, 'stablecoin balance should decrease');
        assertGt(underlying.balanceOf(address(insurancePool)), ipUnderlyingBalance, 'underlying balance should increase');
        assertEq(insurancePool.totalSupply(), ipTotalSupply, 'total supply should not change');
        assertLt(insurancePool.totalAssets(), ipTotalAssets, 'total assets should decrease');
        assertLt(pair.totalCollateral(), pairCollateralBalance, 'pair collateral balance should decrease');
    }

    function test_LiquidationIncentiveCappedAtDefaultMaximum() public {
        buildLiquidatablePositionAtRatio(5_000e18, FULL_FEE_COLLATERAL_RATIO_BPS);
        IncentivePreview memory preview = previewIncentive();

        assertLt(preview.seizedShares, preview.userCollateralShares, 'collateral should not be capped');
        assertGt(preview.rawRewardShares, preview.maxRewardShares, 'raw reward should exceed maximum');
        assertEq(preview.rewardShares, preview.maxRewardShares, 'reward should equal maximum shares');

        executeLiquidationAndAssertReward(preview.rewardAssets);
        assertApproxEqAbs(preview.rewardAssets, liquidationHandler.maxLiquidateIncentive(), 1, 'wrong default maximum');
    }

    function test_LiquidationIncentiveCappedAtConfiguredMaximum() public {
        uint256 configuredMaximum = 10e18;
        vm.prank(address(core));
        liquidationHandler.setMaxLiquidateIncentive(configuredMaximum);
        buildLiquidatablePositionAtRatio(5_000e18, FULL_FEE_COLLATERAL_RATIO_BPS);
        IncentivePreview memory preview = previewIncentive();

        assertGt(preview.rawRewardShares, preview.maxRewardShares, 'raw reward should exceed maximum');
        assertEq(preview.rewardShares, preview.maxRewardShares, 'reward should equal maximum shares');

        executeLiquidationAndAssertReward(preview.rewardAssets);
        assertApproxEqAbs(preview.rewardAssets, configuredMaximum, 1, 'wrong configured maximum');
    }

    function test_LiquidationIncentivePaysUncappedShareOfFullFee() public {
        vm.prank(address(core));
        liquidationHandler.setLiquidateIncentiveShareBps(2_500);
        buildLiquidatablePositionAtRatio(1_000e18, FULL_FEE_COLLATERAL_RATIO_BPS);
        IncentivePreview memory preview = previewIncentive();

        assertLt(preview.seizedShares, preview.userCollateralShares, 'collateral should not be capped');
        assertGt(preview.feeShares, 0, 'fee should be positive');
        assertLt(preview.rawRewardShares, preview.maxRewardShares, 'reward should be below maximum');
        assertEq(preview.rewardShares, preview.rawRewardShares, 'reward should be proportional fee share');

        executeLiquidationAndAssertReward(preview.rewardAssets);
    }

    function test_LiquidationIncentivePaysUncappedShareOfPartialFee() public {
        buildLiquidatablePositionAtRatio(1_000e18, PARTIAL_FEE_COLLATERAL_RATIO_BPS);
        IncentivePreview memory preview = previewIncentive();

        assertEq(preview.seizedShares, preview.userCollateralShares, 'collateral should be capped');
        assertGt(preview.feeShares, 0, 'partial fee should be positive');
        assertLt(preview.feeShares, preview.nominalFeeShares, 'fee should be below nominal fee');
        assertLt(preview.rawRewardShares, preview.maxRewardShares, 'reward should be below maximum');
        assertEq(preview.rewardShares, preview.rawRewardShares, 'reward should be proportional partial fee share');

        executeLiquidationAndAssertReward(preview.rewardAssets);
    }

    function test_LiquidationIncentiveIsZeroForBadDebt() public {
        buildLiquidatablePositionAtRatio(1_000e18, BAD_DEBT_COLLATERAL_RATIO_BPS);
        IncentivePreview memory preview = previewIncentive();

        assertEq(preview.seizedShares, preview.userCollateralShares, 'all collateral should be seized');
        assertEq(preview.feeShares, 0, 'bad debt must not produce a fee');
        assertEq(preview.rewardShares, 0, 'bad debt must not produce a reward');

        executeLiquidationAndAssertReward(0);
    }

    function test_LiquidationIncentiveIgnoresExistingHandlerCollateral() public {
        uint256 existingHandlerCollateral = IERC4626(address(collateral)).convertToShares(100e18);
        deal(address(collateral), address(liquidationHandler), existingHandlerCollateral);
        buildLiquidatablePositionAtRatio(1_000e18, BAD_DEBT_COLLATERAL_RATIO_BPS);
        IncentivePreview memory preview = previewIncentive();

        assertGt(collateral.balanceOf(address(liquidationHandler)), 0, 'handler should have existing collateral');
        assertEq(preview.feeShares, 0, 'current liquidation should have no fee');
        assertEq(preview.rewardShares, 0, 'existing collateral must not subsidize reward');

        executeLiquidationAndAssertReward(0);
    }

    function test_LiquidationIncentiveIsZeroWhenShareIsZero() public {
        vm.prank(address(core));
        liquidationHandler.setLiquidateIncentiveShareBps(0);
        buildLiquidatablePositionAtRatio(1_000e18, FULL_FEE_COLLATERAL_RATIO_BPS);
        IncentivePreview memory preview = previewIncentive();

        assertGt(preview.feeShares, 0, 'fee should be positive');
        assertEq(preview.rewardShares, 0, 'zero share must produce zero reward');

        executeLiquidationAndAssertReward(0);
    }

    function test_LiquidationIncentiveIsZeroWhenMaximumIsZero() public {
        vm.prank(address(core));
        liquidationHandler.setMaxLiquidateIncentive(0);
        buildLiquidatablePositionAtRatio(1_000e18, FULL_FEE_COLLATERAL_RATIO_BPS);
        IncentivePreview memory preview = previewIncentive();

        assertGt(preview.feeShares, 0, 'fee should be positive');
        assertEq(preview.rewardShares, 0, 'zero maximum must produce zero reward');

        executeLiquidationAndAssertReward(0);
    }

    function test_LiquidateSolventBorrowerFails() public {
        uint256 amount = 1000e18;
        borrow(pair, amount, calculateMinUnderlyingNeededForBorrow(amount)); 

        vm.expectRevert(IResupplyPairErrors.BorrowerSolvent.selector);
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
        liquidationHandler.migrateCollateral(address(collateral));

        registry.setLiquidationHandler(address(newLiquidationHandler));
        vm.stopPrank();
        vm.prank(address(newLiquidationHandler));
        liquidationHandler.migrateCollateral(address(collateral));
        assertEq(collateral.balanceOf(address(newLiquidationHandler)), amt);
    }

    function test_distributeCollateralAndClearDebt() public {
        buildLiquidatablePosition();
        withdrawLiquidityFromMarket(); // do this to simulate a market w bad debt.

        uint256 ipStableBalance = stablecoin.balanceOf(address(insurancePool));
        uint256 ipUnderlyingBalance = underlying.balanceOf(address(insurancePool));
        uint256 ipTotalSupply = insurancePool.totalSupply();
        uint256 ipTotalAssets = insurancePool.totalAssets();
        uint256 pairCollateralBalance = pair.totalCollateral();
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
        assertLt(pair.totalCollateral(), pairCollateralBalance, 'pair collateral balance should decrease');
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
        vm.prank(pair.owner());
        pair.setBorrowLimit(50_000e18);
        uint256 DEFAULT_BORROW_AMOUNT = 5_000e18;
        uint256 borrowAmount = pair.minimumBorrowAmount() > DEFAULT_BORROW_AMOUNT ? pair.minimumBorrowAmount() : DEFAULT_BORROW_AMOUNT;
        borrow(pair, borrowAmount, calculateMinUnderlyingNeededForBorrow(borrowAmount)); // borrow while adding collateral
        setOraclePrice(1e10);
    }

    function buildLiquidatablePositionAtRatio(uint256 _borrowAmount, uint256 _collateralRatioBps) internal {
        borrow(pair, _borrowAmount, calculateMinUnderlyingNeededForBorrow(_borrowAmount));
        skip(1);

        uint256 debtAmount = pair.toBorrowAmount(pair.userBorrowShares(address(this)), true, true);
        uint256 userCollateral = pair.userCollateralBalance(address(this));
        uint256 targetPrincipalCollateral = userCollateral * TEST_BPS / _collateralRatioBps;
        uint256 targetExchangeRate = targetPrincipalCollateral * EXCHANGE_PRECISION / debtAmount;

        mockOracle.setPrice(1e36 / targetExchangeRate);
        pair.updateExchangeRate();

        assertGt(getCurrentLTV(pair, address(this)), pair.maxLTV(), 'position should be liquidatable');
    }

    function previewIncentive() internal returns(IncentivePreview memory preview) {
        uint256 borrowShares = pair.userBorrowShares(address(this));
        uint256 debtDown = pair.toBorrowAmount(borrowShares, false, true);
        uint256 debtUp = pair.toBorrowAmount(borrowShares, true, true);
        (,, uint256 exchangeRate) = pair.exchangeRateInfo();

        uint256 principalDown = debtDown * exchangeRate / EXCHANGE_PRECISION;
        uint256 nominalSeizedShares = principalDown * (LIQ_PRECISION + pair.liquidationFee()) / LIQ_PRECISION;
        preview.userCollateralShares = pair.userCollateralBalance(address(this));
        preview.seizedShares = nominalSeizedShares > preview.userCollateralShares
            ? preview.userCollateralShares
            : nominalSeizedShares;
        preview.nominalFeeShares = nominalSeizedShares - principalDown;

        uint256 principalUp = debtUp * exchangeRate / EXCHANGE_PRECISION;
        preview.feeShares = preview.seizedShares > principalUp ? preview.seizedShares - principalUp : 0;
        preview.rawRewardShares = preview.feeShares * liquidationHandler.liquidateIncentiveShareBps() / TEST_BPS;
        preview.maxRewardShares = IERC4626(address(collateral)).convertToShares(liquidationHandler.maxLiquidateIncentive());
        preview.rewardShares = preview.rawRewardShares > preview.maxRewardShares
            ? preview.maxRewardShares
            : preview.rawRewardShares;
        preview.rewardAssets = IERC4626(address(collateral)).previewRedeem(preview.rewardShares);
    }

    function executeLiquidationAndAssertReward(uint256 _expectedRewardAssets) internal {
        uint256 underlyingBefore = underlying.balanceOf(address(this));
        uint256 collateralBefore = collateral.balanceOf(address(this));

        liquidationHandler.liquidate(address(pair), address(this));

        assertApproxEqAbs(
            underlying.balanceOf(address(this)) - underlyingBefore,
            _expectedRewardAssets,
            1,
            'wrong underlying reward'
        );
        assertEq(collateral.balanceOf(address(this)), collateralBefore, 'unexpected collateral-share reward');
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