// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { ResupplyPairConstants } from "src/protocol/pair/ResupplyPairConstants.sol";
import { Setup } from "test/Setup.sol";
import "src/Constants.sol" as Constants;

contract ResupplyAccountingTest is Setup {
    ResupplyPair pair1;
    ResupplyPair pair2;

    address public user9 = address(0xDEADFED5);
    address public user8 = address(0xFA9904);

    function setUp() public override {
        super.setUp();
        deployDefaultLendingPairs();
        address[] memory _pairs = registry.getAllPairAddresses();
        pair1 = ResupplyPair(_pairs[0]); 
        pair2 = ResupplyPair(_pairs[1]);
    }

    function test_redemptionFlow() public {
        // vm.warp(block.timestamp + 1200 days);
        pair1.addInterest(false);
        // ResupplyPair(Constants.Mainnet.FRAXLEND_SFRXETH_FRAX).addInterest(false);
        // vm.warp(block.timestamp + 12 days);
        (, , uint er) = pair1.exchangeRateInfo();
        addCollateralVaultFlow(pair1, user9, 20_000e18);
        borrowStablecoinFlow(pair1, user9, 15_000e18, er);
        console.log("The redemption handler: ", address(redemptionHandler));
        console.log("The redemption fee: ", redemptionHandler.getRedemptionFee(address(pair1), 50e18));

        deal(address(stablecoin), user8, 50e18);
        console.log(stablecoin.balanceOf(user8));

        console.log("Collateral before redeem: ", pair1.collateral().balanceOf(address(pair1)));
        vm.startPrank(user8);
        stablecoin.approve(address(redemptionHandler), 50e18);
        redemptionHandler.redeem(address(pair1), 50e18, 0.1e18, user8);
        console.log(pair1.underlying().balanceOf(user8));
        console.log(pair1.underlying().balanceOf(address(redemptionHandler)));
        vm.stopPrank();
        console.log("Collateral post redeem: ", pair1.collateral().balanceOf(address(pair1)));
        console.log("The ER: ", er);
        console.log("The collateral balance of user9, post redemption: ", pair1.userCollateralBalance(user9));
    }

    // ############################################
    // ############ Unit Test Redeem  #############
    // ############################################
    function test_redeemStablecoinFromPair() public {
        (, , uint er) = pair1.exchangeRateInfo();
        addCollateralVaultFlow(pair1, user9, 20_000e18);
        borrowStablecoinFlow(pair1, user9, 15_000e18, er);
        redeemStablecoinFlow(pair1, user8, 2_000e18);
    }


    // ############################################
    // ############## Fuzz  Redeem  ###############
    // ############################################

    function test_fuzz_redeem(uint96 amount) public {
        (, , uint er) = pair1.exchangeRateInfo();
        addCollateralVaultFlow(pair1, user9, amount);
        amount /= 4;
        amount *= 3;
        uint _amount = 
            bound(
                amount, 
                pair1.minimumBorrowAmount(), 
                pair1.totalDebtAvailable()
            );
        
    
        borrowStablecoinFlow(pair1, user9, _amount, er);
        _amount -= pair1.minimumBorrowAmount();
        redeemStablecoinFlow(pair1, user8, _amount);
    }


    // ############################################
    // ############ Fuzz Add Collateral ###########
    // ############################################

    function test_fuzz_addCollateralVault(uint128 amount) public {
        addCollateralVaultFlow(pair1, user9, amount);
    }

    function test_fuzz_removeCollateralVault(uint128 amount) public {
        uint256 toAddAmount = uint(amount) * 2;
        addCollateralVaultFlow(pair1, user9, toAddAmount);
        removeCollateralVaultFlow(pair1, user9, amount);
    }

    function test_fuzz_addCollateral(uint96 amount) public {
        addCollateralFlow(pair1, user9, amount, Constants.Mainnet.FRAX_ERC20);
    }

    function test_fuzz_removeCollateral(uint64 amount) public {
        uint256 amountToDeposit = uint(amount) * 2;
        amountToDeposit = uint128(bound(amountToDeposit, 0, type(uint128).max - 10));
        addCollateralFlow(pair1, user9, amountToDeposit, Constants.Mainnet.FRAX_ERC20);
        removeCollateralFlow(pair1, user9, amount, Constants.Mainnet.FRAX_ERC20);
    }

    // ############################################
    // ########## Fuzz Borrow Stablecoin ##########
    // ############################################

    function test_fuzz_borrowAssetInvairant(uint96 collateral, uint96 amountToBorrow) public {
        (, , uint er) = pair1.exchangeRateInfo();
        uint256 totalDebtAvailable = pair1.totalDebtAvailable();
        amountToBorrow = uint96(bound(amountToBorrow, 2000e18, totalDebtAvailable));
        addCollateralVaultFlow(pair1, user9, collateral);
        borrowStablecoinFlow(pair1, user9, amountToBorrow, er);
    }

    function test_fuzz_borrowAssetInvairant_varyER(uint96 collateral, uint96 amountToBorrow, uint96 er) public {
        (address oracle, ,) = pair1.exchangeRateInfo();
        address collateralAddress = address(pair1.collateral());
        uint256 totalDebtAvailable = pair1.totalDebtAvailable();
        uint _er = bound(er, 0.5e18, 1000e18); // Seems reasonable
        amountToBorrow = uint96(bound(amountToBorrow, 1000e18, totalDebtAvailable));
        addCollateralVaultFlow(pair1, user9, collateral);
        vm.mockCall(
            oracle,
            abi.encodeWithSignature("getPrices(address)", collateralAddress),
            abi.encode(_er)
        );
        vm.warp(block.timestamp + 10); /// @notice needed to change internal ER
        borrowStablecoinFlow(pair1, user9, amountToBorrow, 1e36/_er);
    }

    // ############################################
    // ###### Flow And Functional Invariants ######
    // ############################################

    function redeemStablecoinFlow(
        ResupplyPair pair,
        address userToRedeem,
        uint256 amountToRedeem
    ) public {
        uint underlyingBalanceBefore = pair.underlying().balanceOf(userToRedeem);
        IERC20 stablecoin = IERC20(redemptionHandler.redemptionToken());

        /// @notice if no available liquidity call will revert in collateralContractRedeem
        uint256 amountCanRedeem = pair.underlying().balanceOf(address(pair.collateral()));

        if (amountToRedeem > amountCanRedeem) amountToRedeem = amountCanRedeem;
        deal(address(stablecoin), userToRedeem, amountToRedeem);

        vm.startPrank(userToRedeem);
        stablecoin.approve(address(redemptionHandler), amountToRedeem);
        (uint totalBorrowAmount, ) = pair.totalBorrow();

        uint fee = redemptionHandler.getRedemptionFee(address(pair), amountToRedeem);
        
        if (totalBorrowAmount <= amountToRedeem) {
            vm.expectRevert(ResupplyPairConstants.InsufficientAssetsForRedemption.selector);
            redemptionHandler.redeem(
                address(pair), 
                amountToRedeem, 
                fee, 
                userToRedeem
            );
            vm.stopPrank();
            return;
        }
        
        redemptionHandler.redeem(
            address(pair), 
            amountToRedeem, 
            fee, 
            userToRedeem
        );
        vm.stopPrank();

        assertApproxEqAbs(
            (amountToRedeem * 99) / 100, // Fee schema
            pair.underlying().balanceOf(userToRedeem) - underlyingBalanceBefore,
            0.001e18
        );
    }

    /// @notice Assumes `user` starts with no balance
    function addCollateralVaultFlow(
        ResupplyPair pair, 
        address user, 
        uint256 amountToAdd
    ) public {
        IERC20 collateral = pair.collateral();
        deal(address(collateral), user, amountToAdd);


        vm.startPrank(user);
        collateral.approve(address(pair), amountToAdd);
        pair.addCollateralVault(amountToAdd, user);
        vm.stopPrank();

        assertEq({
            left: pair.userCollateralBalance(user),
            right: amountToAdd,
            err: "// THEN: Collateral not as expected"
        });
    }

    function removeCollateralVaultFlow(
        ResupplyPair pair, 
        address user, 
        uint256 amountToRemove
    ) public {
        IERC20 collateral = pair.collateral();
        uint256 collateralBefore = collateral.balanceOf(user);
        uint256 userCollateralBalanceBefore = pair1.userCollateralBalance(user);
        
        vm.startPrank(user);
        pair1.removeCollateralVault(
            amountToRemove,
            user
        );
        vm.stopPrank();

        assertEq({
            left: userCollateralBalanceBefore - pair1.userCollateralBalance(user),
            right: amountToRemove,
            err: "// THEN: ResupplyPair collateral balance decremented incorrectly"
        });
        assertEq({
            left: collateral.balanceOf(user) - collateralBefore,
            right: amountToRemove,
            err: "// THEN: Collateral balance not as expected"
        });
    }

    /// @notice Assumes `user` starts with no balance
    function addCollateralFlow(
        ResupplyPair pair,
        address user,
        uint256 amountToAdd,
        address underlying
    ) public {
        IERC20 underlying = IERC20(underlying);
        deal(address(underlying), user, amountToAdd);

        uint256 sharesToReceive = IERC4626(address(pair.collateral())).previewDeposit(amountToAdd);

        vm.startPrank(user);
        underlying.approve(address(pair), amountToAdd);
        pair.addCollateral(amountToAdd, user);
        vm.stopPrank();

        assertEq({
            left: sharesToReceive,
            right: pair.userCollateralBalance(user),
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

        uint256 underlyingToReceive = IERC4626(address(pair.collateral())).previewRedeem(amountToRemove);

        assertEq({
            left: userCollateralBalanceBefore - pair1.userCollateralBalance(user),
            right: amountToRemove,
            err: "// THEN: ResupplyPair collateral balance decremented incorrectly"
        });
        assertEq({
            left: underlying.balanceOf(user) - underlyingBalanceBefore,
            right: underlyingToReceive,
            err: "// THEN: Collateral balance not as expected"
        });
    }

    function borrowStablecoinFlow(
        ResupplyPair pair, 
        address user, 
        uint256 amountToBorrow, 
        uint256 er
    ) public {
        uint256 collat = pair.userCollateralBalance(user);
        uint256 maxDebtToIssue = ((pair.maxLTV()) * collat * 1e18) / (er * 1e5);
        if (amountToBorrow > maxDebtToIssue) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ResupplyPairConstants.Insolvent.selector,
                    amountToBorrow,
                    collat,
                    er
                )
            );
            vm.prank(user);
            pair1.borrow(amountToBorrow, 0, user);
        } else {
            vm.prank(user);
            pair1.borrow(amountToBorrow, 0, user);
            console.log(stablecoin.balanceOf(user));

            assertEq({
                left: stablecoin.balanceOf(user),
                right: amountToBorrow,
                err: "// THEN: stablecoin Issued != amount borrowed"
            });

            /// @notice Given there is no interest accrued 
            ///         debtShare price 1:1 w/ debtAmount
            assertEq({
                left: pair.userBorrowShares(user),
                right: amountToBorrow,
                err: "// THEN: stablecoin Issued != amount borrowed"
            });
        }
    }
}