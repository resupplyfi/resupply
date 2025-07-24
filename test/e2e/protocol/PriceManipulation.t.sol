// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;
import { console } from "lib/forge-std/src/console.sol";
import { Setup } from "test/e2e/Setup.sol";
import { PairTestBase } from "./PairTestBase.t.sol";
import { IResupplyPairErrors } from "src/protocol/pair/IResupplyPairErrors.sol";
import { IBasicVaultOracle } from "src/interfaces/IBasicVaultOracle.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";

contract PairTest is PairTestBase {
    uint256 borrowAmount = 10_000e18;
    uint256 underlyingAmount = 1_000_000e18;

    function setUp() public override {
        super.setUp();
        stablecoin.approve(address(redemptionHandler), type(uint256).max);
        vm.prank(pair.owner());
        pair.setBorrowLimit(500_000e18);
        
    }

    function test_PairInvalidExchangeRate() public {
        super.setUp();
        stablecoin.approve(address(redemptionHandler), type(uint256).max);
        vm.prank(pair.owner());
        pair.setBorrowLimit(500_000e18);

        (address oracle,,) = pair.exchangeRateInfo();

        // Mock the price() call to return 1e36
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IBasicVaultOracle.getPrices.selector),
            abi.encode(1e36+1)
        );

        // Attempt to borrow should fail with InvalidExchangeRate
        deal(address(underlying), address(this), underlyingAmount);
        vm.expectRevert(IResupplyPairErrors.InvalidExchangeRate.selector);
        pair.borrow(borrowAmount, underlyingAmount, address(this));
    }

    function test_OraclePriceOutOfBounds() public {
        super.setUp();
        stablecoin.approve(address(redemptionHandler), type(uint256).max);
        vm.prank(pair.owner());
        pair.setBorrowLimit(500_000e18);

        (address oracle,,) = pair.exchangeRateInfo();

        // Mock the convertToAssets() call on the collateral vault to return an out of bounds price
        address collateral = IResupplyPair(address(pair)).collateral();
        vm.mockCall(
            collateral,
            abi.encodeWithSelector(IERC4626.convertToAssets.selector),
            abi.encode(1e22+1)
        );
        
        // Attempt to borrow should fail with price out of bounds
        deal(address(underlying), address(this), underlyingAmount);
        vm.expectRevert("Price out of bounds");
        pair.borrow(borrowAmount, underlyingAmount, address(this));
    }
}
