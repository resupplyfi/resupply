// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/Setup.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GasMetering is Setup {

    ResupplyPair pair;
    IERC20 collateral;
    IERC20 underlying;

    function setUp() public override {
        super.setUp();

        deployDefaultLendingPairs();
        address[] memory _pairs = registry.getAllPairAddresses();
        pair = ResupplyPair(_pairs[0]); 
        collateral = pair.collateral();
        underlying = pair.underlying();

        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);

        deal(address(collateral), _THIS, 200_000e18);
        deal(address(underlying), _THIS, 200_000e18);
        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);

        // Seed some collateral
        pair.addCollateralVault(100_000e18, _THIS);

        // Setup user1 position
        deal(address(collateral), user1, 200_000e18);
        deal(address(underlying), user1, 200_000e18);
        vm.startPrank(user1);
        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);
        stablecoin.approve(address(redemptionHandler), type(uint256).max);
        pair.addCollateral(100_000e18, user1);
        pair.borrow(90_000e18, 0, user1);
        vm.stopPrank();
    }

    function test_AddCollateralVault() public {
        pair.addCollateralVault(100_000e18, user1);
    }

    function test_AddCollateral() public {
        pair.addCollateral(100_000e18, user1);
    }

    function test_RemoveCollateralVault() public {
        pair.removeCollateralVault(10_000e18, user1);
    }

    function test_RemoveCollateral() public {
        pair.removeCollateral(10_000e18, user1);
    }

    function test_Redeem() public {
        vm.startPrank(user1);
        redemptionHandler.redeemFromPair(
            address(pair), 
            10_000e18, 
            1e18, 
            user1, 
            true
        );
    }
}
