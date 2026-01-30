// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/e2e/Setup.sol";
import { Protocol } from "src/Constants.sol";

contract ReusdOracleTest is Setup {
    function test_OraclePriceVsClampedPrice() public {
        uint256 oracleTarget = 9e17;
        uint256 oraclePrice = 1e36 / oracleTarget;
        vm.mockCall(
            Protocol.REUSD_SCRVUSD_POOL,
            abi.encodeWithSignature("price_oracle(uint256)", 0),
            abi.encode(oraclePrice)
        );
        vm.mockCall(
            Protocol.REGISTRY,
            abi.encodeWithSignature("redemptionHandler()"),
            abi.encode(address(redemptionHandler))
        );

        uint256 floorRate = 95e16;
        uint256 fee = 1e18 - floorRate;
        vm.prank(address(core));
        redemptionHandler.setBaseRedemptionFee(fee);

        uint256 currentPrice = reusdOracle.oraclePriceAsCrvusd();
        uint256 clampedPrice = reusdOracle.priceAsCrvusd();
        assertEq(currentPrice, oracleTarget, "oracle price mismatch");
        assertEq(clampedPrice, floorRate, "clamped price mismatch");
    }

    function test_ReusdOraclePricesAreNonZero() public {
        assertGt(reusdOracle.price(), 0, "price zero");
        assertGt(reusdOracle.priceAsCrvusd(), 0, "priceAsCrvusd zero");
        assertGt(reusdOracle.priceAsFrxusd(), 0, "priceAsFrxusd zero");
        assertGt(reusdOracle.oraclePriceAsCrvusd(), 0, "oraclePriceAsCrvusd zero");
    }
}
