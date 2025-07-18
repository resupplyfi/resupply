// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { Setup } from "test/integration/Setup.sol";
import { Utilities } from "src/protocol/Utilities.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";

contract UtilitiesTest is Setup {
    Utilities public utilities;

    function setUp() public override {
        super.setUp();
        utilities = new Utilities(address(registry));
    }

    function test_GetPairInterestRates() public {
        address[] memory pairs = registry.getAllPairAddresses();
        console.log("Number of pairs:", pairs.length);
        
        for (uint256 i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            uint256 underlyingRate = utilities.getUnderlyingSupplyRate(pair);
            uint256 sfrxusdRate = utilities.sfrxusdRates();
            uint256 rate = utilities.getPairInterestRate(pair);
            console.log("--------------------------------");
            console.log("Pair", pair);
            console.log("%18e", underlyingRate * 365 * 86400, "underlying apr");
            console.log("%18e", sfrxusdRate * 365 * 86400, "sfrxusd apr");
            console.log("%18e", rate * 365 * 86400, "pair APR");
        }
    }
}
