// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/integration/Setup.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { Utilities } from "src/protocol/Utilities.sol";

contract UpdateInterestCalculator is Setup {

    IERC20 public asset;

    InterestRateCalculatorV2 public calcv2;

    function setUp() public override {
        super.setUp();
        asset = IERC20(address(stablecoin));

        //new interest calculator new params
        calcv2 = new InterestRateCalculatorV2(
            address(core),
            2e16 / uint256(365 days) * 2, //4% - we multiply by 2 to adjust for rate ratio base
            0.5e18, //rate ratio base
            0.625e18, //rate ratio base for collateral
            0.2e18, //rate ratio additional (a % of base)
            Protocol.PRICE_WATCHER
        );

        
    }

    function updateRateCalc() internal{
        vm.startPrank(address(core));

        //update all pair's interest calculator
        for (uint256 i = 0; i < pairs.length; i++) {
            address prevCalculator = IResupplyPair(pairs[i]).rateCalculator();
            console.log("previous calculator at pair ", pairs[i], ", = ", prevCalculator);

            //use FALSE in testing only because we want to compare rates with the same state
            //in real deployment this should be TRUE
            IResupplyPair(pairs[i]).setRateCalculator(address(calcv2),false);
        }
        console.log("all pairs set to new calculator");
        vm.stopPrank();
    }

    function printRatesFromUtilities() internal{
        // This helps us test our utilities contract with the new sreusd config
        Utilities utilities = new Utilities(address(registry));
        address[] memory pairs = registry.getAllPairAddresses();
        console.log("Number of pairs:", pairs.length);
        
        for (uint256 i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            uint256 underlyingRate = utilities.getUnderlyingSupplyRate(pair);
            uint256 sfrxusdRate = utilities.sfrxusdRates();
            uint256 rate = utilities.getPairInterestRate(pair);
            console.log("--------------------------------");
            console.log("Pair", pair, IResupplyPair(pair).name());
            console.log("%18e", underlyingRate * 365 * 86400, "underlying apr");
            console.log("%18e", sfrxusdRate * 365 * 86400, "sfrxusd apr");
            console.log("%18e", rate * 365 * 86400, "pair APR");
        }
    }

    function printRatesFromCalculator() internal{
        // This helps us test our utilities contract with the new sreusd config
        Utilities utilities = new Utilities(address(registry));
        address[] memory pairs = registry.getAllPairAddresses();
        console.log("Number of pairs:", pairs.length);
        
        for (uint256 i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            address calculator = IResupplyPair(pair).rateCalculator();
            if(calculator == address(calcv2)){
                uint256 underlyingRate = utilities.getUnderlyingSupplyRate(pair);
                uint256 sfrxusdRate = utilities.sfrxusdRates();
                uint256 rate = calcv2.getPairRate(pair);
                console.log("--------------------------------");
                console.log("Pair", pair, IResupplyPair(pair).name());
                console.log("%18e", underlyingRate * 365 * 86400, "underlying apr");
                console.log("%18e", sfrxusdRate * 365 * 86400, "sfrxusd apr");
                console.log("%18e", rate * 365 * 86400, "pair APR");
            }
        }
    }


    function test_Initialization() public {
        //check previous rates
        printRatesFromUtilities();

        //set new rate calc with same parameters as before
        updateRateCalc();
        vm.startPrank(address(core));
        calcv2.setRateInfo(0.5e18,0.5e18);
        vm.stopPrank();

        //jump forward in time
        // skip(10);

        //check new rates are same as previous
        printRatesFromCalculator();

        //increase base ratio
        vm.startPrank(address(core));
        calcv2.setRateInfo(0.5e18,0.625e18);
        vm.stopPrank();
        console.log("-------------------");
        console.log("rates increased");
        console.log("-------------------");

        //check new rates increased correctly
        printRatesFromCalculator();
    }


    function test_GetPairInterestRates() public {
        printRatesFromUtilities();
    }
}