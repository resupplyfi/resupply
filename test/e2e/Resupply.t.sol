// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BasePairTest } from "test/e2e/BasePairTest.t.sol";
import { console } from "forge-std/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import "src/Constants.sol" as Constants;

contract ResupplyAccountingTest is BasePairTest {
    ResupplyPair pair1;
    ResupplyPair pair2;

    address public user9 = address(0xDEADFED5);

    function setUp() public {
        defaultSetUp();
        deployDefaultLendingPairs();
        address[] memory _pairs = registry.getAllPairAddresses();
        pair1 = ResupplyPair(_pairs[0]); 
        pair2 = ResupplyPair(_pairs[1]);
    }

    // ############################################
    // ############ Fuzz Add Collateral ###########
    // ############################################

    function test_fuzz_addCollateralVault(uint256 amount) public {
        addCollateralVaultFlow(pair1, user9, amount);
    }

    function test_fuzz_removeCollateralVault(uint128 amount) public {
        uint256 toAddAmount = uint(amount) * 2;
        addCollateralVaultFlow(pair1, user9, toAddAmount);
        removeCollateralVaultFlow(pair1, user9, amount);
    }

    function test_fuzz_addCollateral(uint128 amount) public {
        amount = uint128(bound(amount, 0, type(uint128).max - 10));
        addCollateralFlow(pair1, user9, amount, Constants.Mainnet.FRAX_ERC20);
    }

    function test_fuzz_removeCollateral(uint64 amount) public {
        uint256 amountToDeposit = uint(amount) * 2;
        addCollateralFlow(pair1, user9, amountToDeposit, Constants.Mainnet.FRAX_ERC20);
        removeCollateralFlow(pair1, user9, amount, Constants.Mainnet.FRAX_ERC20);
    }

    // ############################################
    // ###### Flow And Functional Invariants ######
    // ############################################

    /// @notice Assumes `user` starts with no balance
    function addCollateralVaultFlow(
        ResupplyPair pair, 
        address user, 
        uint256 amountToAdd
    ) public {
        IERC20 collateral = pair.collateralContract();
        deal(address(collateral), user, amountToAdd);


        vm.startPrank(user);
        collateral.approve(address(pair), amountToAdd);
        pair.addCollateralVault(amountToAdd, user);
        vm.stopPrank();

        assertEq({
            a: pair.userCollateralBalance(user),
            b: amountToAdd,
            err: "// THEN: Collateral not as expected"
        });
    }

    function removeCollateralVaultFlow(
        ResupplyPair pair, 
        address user, 
        uint256 amountToRemove
    ) public {
        IERC20 collateral = pair.collateralContract();
        uint256 collateralBefore = collateral.balanceOf(user);
        uint256 userCollateralBalanceBefore = pair1.userCollateralBalance(user);
        
        vm.startPrank(user);
        pair1.removeCollateralVault(
            amountToRemove,
            user
        );
        vm.stopPrank();

        assertEq({
            a: userCollateralBalanceBefore - pair1.userCollateralBalance(user),
            b: amountToRemove,
            err: "// THEN: ResupplyPair collateral balance decremented incorrectly"
        });
        assertEq({
            a: collateral.balanceOf(user) - collateralBefore,
            b: amountToRemove,
            err: "// THEN: Collateral balance not as expected"
        });
    }

    /// @notice Assumes `user` starts with no balance
    function addCollateralFlow(
        ResupplyPair pair,
        address user,
        uint256 amountToAdd,
        address underlyingAsset
    ) public {
        IERC20 underlying = IERC20(underlyingAsset);
        deal(underlyingAsset, user, amountToAdd);

        uint256 sharesToReceive = IERC4626(address(pair.collateralContract())).previewDeposit(amountToAdd);

        vm.startPrank(user);
        underlying.approve(address(pair), amountToAdd);
        pair.addCollateral(amountToAdd, user);
        vm.stopPrank();

        assertEq({
            a: sharesToReceive,
            b: pair.userCollateralBalance(user),
            err: "// THEN: userCollateralBalance not as expected"
        });
    }

    function removeCollateralFlow(
        ResupplyPair pair,
        address user,
        uint256 amountToRemove,
        address underlyingAddress
    ) public {
        IERC20 underlying = IERC20(underlyingAddress);
        uint256 underlyingBalanceBefore = underlying.balanceOf(user);
        uint256 userCollateralBalanceBefore = pair.userCollateralBalance(user);

        vm.startPrank(user);
        pair1.removeCollateral(
            amountToRemove,
            user
        );
        vm.stopPrank();

        uint256 underlyingToReceive = IERC4626(address(pair.collateralContract())).previewRedeem(amountToRemove);

        assertEq({
            a: userCollateralBalanceBefore - pair1.userCollateralBalance(user),
            b: amountToRemove,
            err: "// THEN: ResupplyPair collateral balance decremented incorrectly"
        });
        assertEq({
            a: underlying.balanceOf(user) - underlyingBalanceBefore,
            b: underlyingToReceive,
            err: "// THEN: Collateral balance not as expected"
        });
    }
}