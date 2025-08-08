// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/integration/Setup.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { PriceWatcher } from "src/protocol/PriceWatcher.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { MockReUsdOracle } from "test/mocks/MockReUsdOracle.sol";

contract PriceWatcherTest is Setup {
    PriceWatcher public priceWatcher;
    InterestRateCalculatorV2 public interestRateCalculator;
    address[] public pairs;
    uint256 public UPDATE_INTERVAL;
    MockReUsdOracle public mockReUsdOracle;

    function setUp() public override {
        super.setUp();
        // set up mock oracle
        mockReUsdOracle = new MockReUsdOracle();
        vm.prank(address(core));
        registry.setAddress("REUSD_ORACLE", address(mockReUsdOracle));
        // set up price watcher
        priceWatcher = new PriceWatcher(address(registry));
        UPDATE_INTERVAL = priceWatcher.UPDATE_INTERVAL();
        interestRateCalculator = new InterestRateCalculatorV2(
            "V2",
            2e16 / uint256(365 days),//2%
            5e17,
            1e17,
            address(priceWatcher)
        );
        pairs = registry.getAllPairAddresses();
        vm.startPrank(address(core));
        for (uint256 i = 0; i < pairs.length; i++) {
            IResupplyPair pair = IResupplyPair(pairs[i]);
            pair.setRateCalculator(address(interestRateCalculator), true);
        }
        vm.stopPrank();
    }

    // TODO: Test that price ratio is always within range
    // TODO: Test changing index out of order
    // TODO: Test that price ratio is updated correctly
    // TODO: Test that interest rate is updated correctly

    function test_updatePairsPriceHistory() public {
        printCurrentWeight();
        skip(5 days);
        // Update all pairs
        uint256 ftime = getFloorTimestamp(block.timestamp);
        uint256 idx;
        
        for (uint256 i = 0; i < 25; i++) {
            priceWatcher.updatePriceData();
            assertLe(priceWatcher.timeMap(ftime), priceWatcher.priceDataLength() - 1);
            skip(UPDATE_INTERVAL);
        }

        priceWatcher.updatePriceData();
        for (uint256 i = 0; i < pairs.length; i++) {
            assertPriceRatioWithinRange(priceWatcher.findPairPriceWeight(pairs[i]));
        }

        PriceWatcher.PriceData memory latestPriceData = priceWatcher.latestPriceData();
        assertPriceRatioWithinRange(latestPriceData.weight);
        printCurrentWeight();

        ftime = getFloorTimestamp(block.timestamp);
        // Let's print all indexes and corresponding timestamps
        while(idx != 1){
            ftime -= UPDATE_INTERVAL;
            idx = priceWatcher.timeMap(ftime);
            console.log("ftime", ftime, "idx", idx);
        }
    }

    function test_FindPairPriceWeight() public {
        // In this test we use two sample pairs to test the prices returned by the price watcher
        address pair1 = pairs[0];
        address pair2 = pairs[1];
        uint256 weight1;
        uint256 weight2;
        
        // Step 1. Start with .99 peg and sync to give us some weight (1e6)
        skip(UPDATE_INTERVAL);
        mockReUsdOracle.setPrice(0.99e18);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        IResupplyPair(pair2).addInterest(false);

        skip(UPDATE_INTERVAL);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false); // checkpoints our weight
        IResupplyPair(pair2).addInterest(false);
        weight1 = priceWatcher.findPairPriceWeight(pair1);
        weight2 = priceWatcher.findPairPriceWeight(pair2);
        (uint64 lastPairUpdate, ,) = IResupplyPair(pair2).currentRateInfo();
        console.log("---Step 1---");
        PriceWatcher.PriceData memory latestPriceData = priceWatcher.latestPriceData();
        console.log(lastPairUpdate, block.timestamp, latestPriceData.timestamp);
        console.log("pair 1:", weight1, "pair 2:", weight2);
        assertEq(weight1, 1e6);
        assertEq(weight2, 1e6);

        // Step 2. Now increase the peg to give zero weight
        skip(UPDATE_INTERVAL);
        mockReUsdOracle.setPrice(1e18);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        skip(UPDATE_INTERVAL);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        weight1 = priceWatcher.findPairPriceWeight(pair1);
        weight2 = priceWatcher.findPairPriceWeight(pair2);
        console.log("---Step 2---");
        (lastPairUpdate, ,) = IResupplyPair(pair2).currentRateInfo();
        console.log("lastPairUpdate", lastPairUpdate, getFloorTimestamp(uint256(lastPairUpdate)));
        console.log("pair 1:", weight1, "pair 2:", weight2);
        assertEq(weight1, 0);
        assertEq(weight2, uint256(1e6) / 2); // We did not sync pair 2, so it should still have weight

        // Step 3. Sync pair 1
        skip(UPDATE_INTERVAL);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        weight1 = priceWatcher.findPairPriceWeight(pair1);
        weight2 = priceWatcher.findPairPriceWeight(pair2);
        console.log("---Step 3---");
        console.log("pair 1:", weight1, "pair 2:", weight2);
        assertEq(weight1, 0);
        assertEq(weight2, uint256(1e6) / 3); // We still did not sync pair 2, so it should still have weight

        skip(UPDATE_INTERVAL);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        IResupplyPair(pair2).addInterest(false);
        weight1 = priceWatcher.findPairPriceWeight(pair1);
        weight2 = priceWatcher.findPairPriceWeight(pair2);
        console.log("pair 1:", weight1, "pair 2:", weight2);
        assertEq(weight1, 0);
        assertEq(weight2, 0); // since we finally called addInterest on pair 2, it should have weight 0
        printPriceNodesData();
    }

    function test_InterestRateCalculation() public {
        address pair1 = pairs[0];
        address pair2 = pairs[1];
        uint256 rate1;
        uint256 rate2;
        
        // Step 1. Start with .99 peg and sync to give us some weight (1e6)
        skip(UPDATE_INTERVAL);
        mockReUsdOracle.setPrice(0.99e18);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        IResupplyPair(pair2).addInterest(false);

        skip(UPDATE_INTERVAL);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false); // checkpoints our weight
        IResupplyPair(pair2).addInterest(false);
        rate1 = getNewInterestRate(pair1);
        rate2 = getNewInterestRate(pair2);
        (uint64 lastPairUpdate, ,) = IResupplyPair(pair2).currentRateInfo();
        console.log("---Step 1---");
        console.log("pair 1:", rate1, "pair 2:", rate2);


        // Step 2. Now increase the peg to give zero weight
        skip(UPDATE_INTERVAL);
        mockReUsdOracle.setPrice(0.98e18);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        skip(UPDATE_INTERVAL);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        rate1 = getNewInterestRate(pair1);
        rate2 = getNewInterestRate(pair2);
        console.log("---Step 2---");
        console.log("pair 1:", rate1, "pair 2:", rate2);

        // Step 3. Sync pair 1
        mockReUsdOracle.setPrice(1e18);
        skip(UPDATE_INTERVAL);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        rate1 = getNewInterestRate(pair1);
        rate2 = getNewInterestRate(pair2);
        console.log("---Step 3---");
        console.log("pair 1:", rate1, "pair 2:", rate2);    

        skip(UPDATE_INTERVAL);
        priceWatcher.updatePriceData();
        IResupplyPair(pair1).addInterest(false);
        IResupplyPair(pair2).addInterest(false);
        rate1 = getNewInterestRate(pair1);
        rate2 = getNewInterestRate(pair2);
        console.log("---Step 4---");
        console.log("pair 1:", rate1, "pair 2:", rate2);

        printPriceNodesData();
    }

    function assertPriceRatioWithinRange(uint256 priceRatio) public {
        assertGe(priceRatio, 0);
        assertLe(priceRatio, 1e6);
    }

    function printCurrentWeight() public {
        console.log("Current weight:", priceWatcher.getCurrentWeight());
    }
    
    function getFloorTimestamp(uint256 _timestamp) public view returns(uint256) {
        return (_timestamp/UPDATE_INTERVAL) * UPDATE_INTERVAL;
    }

    function printPriceNodesData() public {
        console.log("\n---Node Data---");
        for (uint256 i = 0; i < priceWatcher.priceDataLength(); i++) {
            PriceWatcher.PriceData memory priceData = priceWatcher.priceDataAtIndex(i);
            uint ftime = getFloorTimestamp(priceData.timestamp);
            console.log(i, priceData.totalWeight, priceData.weight, ftime);
        }
    }

    function getNewInterestRate(address _pair) public returns(uint256) {
        address collateral = IResupplyPair(_pair).collateral();
        (, IResupplyPair.CurrentRateInfo memory currentRateInfo,,) = IResupplyPair(_pair).addInterest(true);
        address calculator = IResupplyPair(_pair).rateCalculator();
        skip(1);
        vm.prank(_pair);
        (uint256 newRatePerSec, ) = InterestRateCalculatorV2(calculator).getNewRate(
            collateral,
            block.timestamp - uint256(currentRateInfo.lastTimestamp),
            currentRateInfo.lastShares
        );
        return newRatePerSec * 60 * 60 * 24 * 365;
    }

    // TODO: Test that tries to call `findPairPriceWeight` after making last pair update stale
    // TODO: Check actual interest rate calculation on each test
    // TODO: Call multiple times in same block
    // TODO: Create a fake oracle that lets me set price
    // TODO: add a test that goes from max to min and makes sure
    // TODO: test triggers on reward claim, etc
}