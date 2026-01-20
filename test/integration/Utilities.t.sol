// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { Setup } from "test/integration/Setup.sol";
import { Utilities } from "src/protocol/Utilities.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";

contract UtilitiesTest is Setup {
    Utilities public utilities;
    InterestRateCalculatorV2 public calcv2;

    function setUp() public override {
        super.setUp();
        utilities = new Utilities(address(registry));

        //new interest calculator new params
        calcv2 = new InterestRateCalculatorV2(
            address(core),
            2e16 / uint256(365 days) * 2, //4% - we multiply by 2 to adjust for rate ratio base
            0.5e18, //rate ratio base
            0.625e18, //rate ratio base for collateral
            0.2e18, //rate ratio additional (a % of base)
            Protocol.PRICE_WATCHER
        );
        _updateRateCalc();
    }

    function _updateRateCalc() internal{
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

    function test_SavingsRate() public {
        uint256 sreusdRate = utilities.savingsRate(Protocol.SREUSD);
        uint256 sfrxusdRate = utilities.savingsRate(Mainnet.SFRXUSD_ERC20);
        uint256 sreusdRate2 = utilities.sreusdRates();
        uint256 sfrxusdRate2 = utilities.sfrxusdRates();
        console.log("%18e", sreusdRate * 365 * 1 days, "sreusdRate");
        console.log("%18e", sfrxusdRate * 365 * 1 days, "sfrxusdRate");
        console.log("%18e", sreusdRate2 * 365 * 1 days, "sreusdRate2");
        console.log("%18e", sfrxusdRate2 * 365 * 1 days, "sfrxusdRate2");
        assertEq(sreusdRate, sreusdRate2);
        assertEq(sfrxusdRate, sfrxusdRate2);
    }

    function test_GetPairInterestRates() public {
        address[] memory pairs = registry.getAllPairAddresses();
        console.log("Number of pairs:", pairs.length);
        console.log("Block timestamp:", block.timestamp);
        console.log("Block number:", block.number);
        for (uint256 i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            uint256 underlyingRate = utilities.getUnderlyingSupplyRate(pair);
            uint256 sfrxusdRate = utilities.sfrxusdRates();
            uint256 rate = utilities.getPairInterestRate(pair);
            address collateral = IResupplyPair(pair).collateral();
            console.log("--------------------------------");
            console.log("Pair", pair, IResupplyPair(pair).name());
            console.log("%18e", underlyingRate * 365 * 86400, "underlying apr");
            console.log("%18e", sfrxusdRate * 365 * 86400, "sfrxusd apr");
            console.log("%18e", rate * 365 * 86400, "pair APR");
        }
    }
}
