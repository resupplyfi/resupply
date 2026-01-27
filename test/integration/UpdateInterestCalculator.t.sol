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

        //shouldnt need to do this
        //checkpoint all
        // for (uint256 i = 0; i < pairs.length; i++) {
        //     IResupplyPair(pairs[i]).addInterest(false);
        // }

        // //move time ahead 
        // skip(100);

        //show rates before we update
        printRatesFromUtilities();

        //update calculator
        _updateRateCalc();
    }

    function _updateRateCalc() internal{
        vm.startPrank(address(core));

        //create a new calculator
        // calcv2 = new InterestRateCalculatorV2(
        //     address(core),
        //     2e16 / uint256(365 days) * 2, //4% - we multiply by 2 to adjust for rate ratio base
        //     0.5e18, //rate ratio base
        //     0.625e18, //rate ratio base for collateral
        //     0.2e18, //rate ratio additional (a % of base)
        //     Protocol.PRICE_WATCHER
        // );

        //grab deployed version for final testing
        calcv2 = InterestRateCalculatorV2(Protocol.INTEREST_RATE_CALCULATOR_V2);

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
        Utilities utilities = Utilities(address(0x2B2df195212766FD87fDc8415D67E5Aba5dCaa04)); //old utilities
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
        // Utilities utilities = new Utilities(address(registry)); //deploy new utilities
        Utilities utilities = Utilities(Protocol.UTILITIES); //already deployed so grab live version
        address[] memory pairs = registry.getAllPairAddresses();
        console.log("Number of pairs:", pairs.length);
        
        for (uint256 i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            address calculator = IResupplyPair(pair).rateCalculator();
            if(calculator == address(calcv2)){
                uint256 underlyingRate = utilities.getUnderlyingSupplyRate(pair);
                uint256 sfrxusdRate = utilities.sfrxusdRates();
                uint256 rate = utilities.getPairInterestRate(pair);
                assertGt(rate, 0, "rate should never be 0");
                console.log("--------------------------------");
                console.log("Pair", pair, IResupplyPair(pair).name());
                console.log("%18e", underlyingRate * 365 * 86400, "underlying apr");
                console.log("%18e", sfrxusdRate * 365 * 86400, "sfrxusd apr");
                console.log("%18e", rate * 365 * 86400, "pair APR");
            }
        }
    }


    function test_Initialization() public {
        //set calc to same ratio as before
        
        vm.startPrank(address(core));
        calcv2.setRateInfo(0.5e18,0.5e18);
        vm.stopPrank();

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

    function test_SetRateInfo_RevertsWhenTotalAbove100() public {
        vm.startPrank(address(core));
        // values violate: base + base*additional >= 1e18
        vm.expectRevert("total rate must be below 100%");
        calcv2.setRateInfo(0.90e18, 0.5e18); // with additional=0.2e18 this violates
        vm.stopPrank();
    }

    function test_AccessControlOnSetRateInfo() public {
        vm.expectRevert(); // or your specific revert selector/message
        calcv2.setRateInfo(0.5e18, 0.5e18);
    }
}