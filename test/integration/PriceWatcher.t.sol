// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/integration/Setup.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { PriceWatcher } from "src/protocol/PriceWatcher.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";

contract PriceWatcherTest is Setup {
    PriceWatcher public priceWatcher;
    InterestRateCalculatorV2 public interestRateCalculator;
    address[] public pairs;
    uint256 public UPDATE_INTERVAL;
    uint256 public INTERIM_UPDATE_INTERVAL;

    function setUp() public override {
        super.setUp();
        priceWatcher = new PriceWatcher(address(registry));
        UPDATE_INTERVAL = priceWatcher.UPDATE_INTERVAL();
        INTERIM_UPDATE_INTERVAL = priceWatcher.INTERIM_UPDATE_INTERVAL();
        interestRateCalculator = new InterestRateCalculatorV2(
            "V2",
            2e16 / uint256(365 days),//2%
            2,
            2,
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
        uint256 ftime = floor(block.timestamp);
        uint256 idx;
        
        for (uint256 i = 0; i < 25; i++) {
            for (uint256 i = 0; i < 12; i++) {
                priceWatcher.updatePriceData();
                skip(INTERIM_UPDATE_INTERVAL);
            }
            assertLe(priceWatcher.timeMap(ftime), priceWatcher.priceDataLength() - 1);
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
}