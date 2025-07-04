// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { ERC20, LinearRewardsErc4626 } from "src/protocol/sreusd/LinearRewardsErc4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/e2e/Setup.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";
import { MockReUsdOracle } from "test/mocks/MockReUsdOracle.sol";
import { PairTestBase } from "test/e2e/protocol/PairTestBase.t.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";

contract SreUSDIntegrationTest is PairTestBase {
    MockReUsdOracle public mockReUsdOracle;
    IERC20 public asset;
    address[] public pairs;

    function setUp() public override {
        super.setUp();
        asset = IERC20(address(stablecoin));
        console.log("Total pairs found:", registry.registeredPairsLength());
        require(registry.registeredPairsLength() > 0, "Pairs not found but needed");

        // Setup mock oracle for easier price manipulation in tests
        mockReUsdOracle = new MockReUsdOracle();
        vm.startPrank(address(core));
        registry.setAddress("REUSD_ORACLE", address(mockReUsdOracle));
        priceWatcher.setOracle();
        vm.stopPrank();
        pairs = registry.getAllPairAddresses();
        console.log("Number of pairs found:", pairs.length);
        depositToGovStaker(1000e18);
        distributeWeeklyFees();
    }

    function test_PegBasedInterestRateChanges() public {
        address pair = pairs[0];
        // Start with peg at 1.0 (no additional fees)
        setPeg(1e18);
        uint256 initialRate = getInterestRate(pair);
        console.log("Initial rate at peg 1.0:", initialRate);

        // Move peg to 0.99 and checkpoint (should increase fees)
        setPeg(0.99e18);
        IResupplyPair(pair).addInterest(false);
        skip(epochLength);
        uint256 newRate = getInterestRate(pair);
        console.log("New rate at peg 0.99:", newRate);
        console.log("Rate increase:", newRate - initialRate);
        assertGt(newRate, initialRate, "Interest rate should increase when off peg");
    }

    function test_FeeDistributionToSreUSD() public {
        depositToStakedStable(1000e18);
        address pair = pairs[0];
        uint256 borrowAmount = 10_000e18;
        borrow(ResupplyPair(pair), borrowAmount, borrowAmount*2);
        // Advance time and add interest to generate fees
        skip(1 days);
        IResupplyPair(pair).addInterest(false);
        uint256 initialSreUSDBalance = asset.balanceOf(address(stakedStable));
        
        // Advance two epochs needed to realize fee distribution
        advanceEpochsWithdrawFeesAndDistributeFees(2);
        
        // Check that sreUSD received fees
        uint256 finalSreUSDBalance = asset.balanceOf(address(stakedStable));
        assertGt(finalSreUSDBalance, initialSreUSDBalance, "sreUSD should receive fees");
        uint256 feesWhenOnPeg = finalSreUSDBalance - initialSreUSDBalance;

        // Let's do another round, but this time with off peg fees
        setPeg(0.99e18);
        initialSreUSDBalance = asset.balanceOf(address(stakedStable));
        advanceEpochsWithdrawFeesAndDistributeFees(2);
        finalSreUSDBalance = asset.balanceOf(address(stakedStable));
        uint256 feesWhenOffPeg = finalSreUSDBalance - initialSreUSDBalance;

        console.log("sreUSD received fees when on peg:", feesWhenOnPeg);
        console.log("sreUSD received fees when off peg:", feesWhenOffPeg);
        assertGt(feesWhenOffPeg, feesWhenOnPeg, "sreUSD should receive more fees when off peg");
    }

    function test_InterestRatesIncreaseWhenOffPeg() public {
        address pair = pairs[0];
        uint256 borrowAmount = 10_000e18;
        borrow(ResupplyPair(pair), borrowAmount, borrowAmount*2);
        
        // Step 1
        setPeg(1e18);
        IResupplyPair(pair).addInterest(false);
        uint256 rate = getInterestRate(pair);
        console.log("Step 1 rate:", rate);
        advanceEpochs(1);

        // Step 2
        setPeg(0.99e18);
        IResupplyPair(pair).addInterest(false);
        console.log("Step 2 rate:", rate, "--->", getInterestRate(pair));
        assertLt(rate, getInterestRate(pair), "Rate should decrease when off peg");
        rate = getInterestRate(pair);
        advanceEpochs(1);
        
        // Step 3
        setPeg(0.98e18);
        IResupplyPair(pair).addInterest(false);
        console.log("Step 3 rate:", rate, "--->", getInterestRate(pair));
        assertLt(rate, getInterestRate(pair), "Rate should decrease when off peg");
        rate = getInterestRate(pair);
        advanceEpochs(1);

        // Step 4: Back to peg
        setPeg(1e18);
        IResupplyPair(pair).addInterest(false);
        console.log("Step 4 rate:", rate, "--->", getInterestRate(pair));
        assertGt(rate, getInterestRate(pair), "Rate should increase when back to peg");
        rate = getInterestRate(pair);
        advanceEpochs(1);
        
        advanceEpochsWithdrawFeesAndDistributeFees(2);
        uint256 sreUSDBalance = asset.balanceOf(address(stakedStable));
        console.log("sreUSD total fees received:", sreUSDBalance);
        assertGt(sreUSDBalance, 0, "sreUSD should have received fees");
    }

    function test_SreUSDYieldGeneration() public {
        // Setup sreUSD deposits
        uint256 depositAmount = 1000e18;
        deal(address(asset), address(user1), depositAmount);
        vm.startPrank(address(user1));
        asset.approve(address(stakedStable), depositAmount);
        uint256 shares = stakedStable.deposit(depositAmount, address(user1));
        vm.stopPrank();
        
        uint256 initialShares = stakedStable.balanceOf(address(user1));
        uint256 initialPPS = stakedStable.pricePerShare();
        
        // Generate fees over multiple epochs
        for (uint256 i = 0; i < 3; i++) {
            address pair = pairs[0];
            uint256 borrowAmount = 10_000e18;
            borrow(ResupplyPair(pair), borrowAmount, borrowAmount*2);
            skip(1 days);
            IResupplyPair(pair).addInterest(false);
            advanceEpochsWithdrawFeesAndDistributeFees(1);
            stakedStable.syncRewardsAndDistribution();
        }
        
        // Check that sreUSD price per share increased
        uint256 finalPPS = stakedStable.pricePerShare();
        assertGt(finalPPS, initialPPS, "sreUSD should generate yield");
        console.log("Price per share gain:", finalPPS - initialPPS);
    }

    function test_TimeWeightedFeesAndLogger() public {
        address pair = pairs[0];
        uint256 borrowAmount = 10_000e18;
        borrow(ResupplyPair(pair), borrowAmount, borrowAmount*2);

        // Start at peg and skip to fresh epoch
        setPeg(1e18);
        advanceEpochsWithdrawFeesAndDistributeFees(1);

        // EPOCH 1: Variable peg
        uint256 startEpoch = feeDeposit.getEpoch();
        skip(1 days);
        IResupplyPair(pair).addInterest(false);
        setPeg(0.98e18);
        skip(2 days);
        IResupplyPair(pair).addInterest(false);
        setPeg(1e18);
        skip(1 days);
        IResupplyPair(pair).addInterest(false);
        advanceEpochsWithdrawFeesAndDistributeFees(1);

        // EPOCH 2: Fixed at peg        
        advanceEpochsWithdrawFeesAndDistributeFees(1);

        // EPOCH 3: Fixed off peg
        setPeg(0.98e18);
        advanceEpochsWithdrawFeesAndDistributeFees(2);

        uint256 sreUSDBalance = asset.balanceOf(address(stakedStable));
        assertGt(sreUSDBalance, 0, "sreUSD should have received fees");
        uint256 feesEpoch1;
        uint256 feesEpoch2;
        uint256 feesEpoch3;
        for(uint256 i = 0; i < 3; i++){
            uint256 interestFees = feeLogger.epochInterestFees(startEpoch + i);
            console.log("Interest fees for epoch", startEpoch + i, ":", interestFees);
            if(i == 0) feesEpoch1 = interestFees;
            if(i == 1) feesEpoch2 = interestFees;
            if(i == 2) feesEpoch3 = interestFees;
        }
        // Based on our peg settings, the highest earning epochs should be: 3, 1, 2
        assertGt(feesEpoch1, 0, "Fees for epoch 1 should be greater than 0");
        assertGt(feesEpoch1, feesEpoch2, "Fees for epoch 2 should be greater than fees for epoch 1");
        assertGt(feesEpoch3, feesEpoch1, "Fees for epoch 3 should be greater than fees for epoch 1");
    }

    function getInterestRate(address pair) public returns (uint256) {
        // Trigger interest calculation and get new rate
        IResupplyPair(pair).addInterest(false);
        
        // Get the current rate from the calculator
        address calculator = IResupplyPair(pair).rateCalculator();
        address collateral = IResupplyPair(pair).collateral();
        vm.prank(address(pair));
        (uint256 ratePerSec, ) = InterestRateCalculatorV2(calculator).getNewRate(
            collateral,
            1 days, // time span
            1e18    // shares
        );
        return ratePerSec * 365 days; // Convert to annual rate
    }

    function advanceEpochsWithdrawFeesAndDistributeFees(uint256 epochs) internal {
        for (uint256 i = 0; i < epochs; i++) {
            advanceEpochs(1);
            // Distributor must go first
            distributeWeeklyFees();
            // Withdraw fees comes next
            for (uint256 j = 0; j < pairs.length; j++) {
                address pair = pairs[j];
                IResupplyPair(pair).addInterest(false);
                if(!hasWithdrawnFees(pair)) IResupplyPair(pair).withdrawFees();
            }
        }
    }

    function distributeWeeklyFees() internal {
        if(hasDistributedWeeklyFees()) return;
        uint256 total = stablecoin.balanceOf(address(feeDeposit));
        console.log("---------- Epoch ", feeDeposit.getEpoch(), " distributions ----------");
        console.log("Total fees distributed:", total);
        uint256 sreUsdBalance = stablecoin.balanceOf(address(stakedStable));
        uint256 ipBalance = stablecoin.balanceOf(address(ipEmissionStream));
        uint256 stakerBalance = stablecoin.balanceOf(address(staker));
        uint256 treasuryBalance = stablecoin.balanceOf(address(treasury));
        vm.prank(address(core));
        feeDepositController.distribute();
        if(total == 0) return;
        uint256 sreUsdGain = stablecoin.balanceOf(address(stakedStable)) - sreUsdBalance;
        uint256 ipGain = stablecoin.balanceOf(address(ipEmissionStream)) - ipBalance;
        uint256 stakerGain = stablecoin.balanceOf(address(staker)) - stakerBalance;
        uint256 treasuryGain = stablecoin.balanceOf(address(treasury)) - treasuryBalance;
        
        console.log("SreUSD split:", sreUsdGain, "%", sreUsdGain * 1e4 / total);
        console.log("Insurance pool split:", ipGain, "%", ipGain * 1e4 / total);
        console.log("Staker split:", stakerGain, "%", stakerGain * 1e4 / total);
        console.log("Treasury split:", treasuryGain, "%", treasuryGain * 1e4 / total);
    }

    function advanceEpochs(uint256 epochs) internal {
        for (uint256 i = 0; i < epochs; i++) {
            vm.warp(getNextEpochStart());
        }
    }

    function getNextEpochStart() internal view returns (uint256) {
        return (vm.getBlockTimestamp() + epochLength) / epochLength * epochLength;
    }

    function hasDistributedWeeklyFees() internal view returns (bool) {
        return feeDeposit.lastDistributedEpoch() >= feeDeposit.getEpoch();
    }
    
    function hasWithdrawnFees(address pair) internal returns (bool) {
        return IResupplyPair(pair).lastFeeEpoch() >= IResupplyPair(pair).getEpoch();
    }

    function depositToGovStaker(uint256 amount) internal {
        deal(address(govToken), address(user1), amount);
        vm.startPrank(address(user1));
        govToken.approve(address(staker), 1000e18);
        staker.stake(amount);
        vm.stopPrank();
    }

    function depositToStakedStable(uint256 amount) internal {
        deal(address(asset), address(user1), amount);
        vm.startPrank(address(user1));
        asset.approve(address(stakedStable), amount);
        stakedStable.deposit(amount, address(user1));
        vm.stopPrank();
    }

    function setPeg(uint256 price) internal {
        mockReUsdOracle.setPrice(price);
        priceWatcher.updatePriceData();
        skip(priceWatcher.UPDATE_INTERVAL());
        priceWatcher.updatePriceData();
    }
}