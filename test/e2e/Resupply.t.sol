// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { ResupplyPairConstants } from "src/protocol/pair/ResupplyPairConstants.sol";
import { Setup } from "test/Setup.sol";
import "src/Constants.sol" as Constants;

contract ResupplyAccountingTest is Setup {
    uint256 public PRECISION;
    ResupplyPair pair1;
    ResupplyPair pair2;

    address public user9 = address(0xDEADFED5);
    address public user8 = address(0xFA9904);
    address public user7 = address(0xCC99);

    function setUp() public override {
        super.setUp();
        deployDefaultLendingPairs();
        address[] memory _pairs = registry.getAllPairAddresses();
        pair1 = ResupplyPair(_pairs[0]); 
        pair2 = ResupplyPair(_pairs[1]);
        stablecoin.approve(address(redemptionHandler), type(uint256).max);
        PRECISION = redemptionHandler.PRECISION();
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
    // ############ Fuzz  liquidate  ##############
    // ############################################

    function test_fuzz_liquidate(uint128 collateralAmount) public {
        pair1.addInterest(false);
        /// @notice Bound
        collateralAmount = uint96(bound(collateralAmount, 2_000e18, 5_000_000e18));
        addCollateralFlow(
            pair1,
            user7,
            collateralAmount,
            Constants.Mainnet.FRAX_ERC20
        );
        uint256 collateral = pair1.userCollateralBalance(user7);
        uint256 ltv = pair1.maxLTV();
        (, , uint er) = pair1.exchangeRateInfo();
        uint256 maxToBorrow = (ltv * collateral * (1e36 / er)) / (1e18 * 1e5);
        borrowStablecoinFlow(
            pair1, 
            user7, 
            maxToBorrow,
            er
        );
        liquidationFlow(
            pair1,
            user7,
            er
        );
    }

    // ############################################
    // ############## Fuzz  Repay  ###############
    // ############################################

    function test_fuzz_repay(uint128 amount) public {
        uint amount = 10_000e18 + uint(amount);
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
        
        amount = bound(_amount, 1000e18, _amount);

        repayDebtFlow(pair1, user9, amount);
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
        IERC20 stablecoin = IERC20(redemptionHandler.debtToken());

        /// @notice if no available liquidity call will revert in collateralContractRedeem
        uint256 amountCanRedeem = pair.underlying().balanceOf(address(pair.collateral()));

        if (amountToRedeem > amountCanRedeem) amountToRedeem = amountCanRedeem;
        deal(address(stablecoin), userToRedeem, amountToRedeem);

        vm.startPrank(userToRedeem);
        stablecoin.approve(address(redemptionHandler), amountToRedeem);
        (uint totalBorrowAmount, ) = pair.totalBorrow();

        uint _fee = redemptionHandler.getRedemptionFeePct(address(pair), amountToRedeem);
        
        uint256 collateralValue = amountToRedeem * (1e18 - _fee) / 1e18;
        uint256 platformFee = (amountToRedeem - collateralValue) * pair.protocolRedemptionFee() / 1e18;
        uint256 debtReduction = amountToRedeem - platformFee;

        if (
            totalBorrowAmount <= debtReduction ||
            totalBorrowAmount - debtReduction < pair.minimumLeftoverDebt()
        ) {
            vm.expectRevert(ResupplyPairConstants.InsufficientDebtToRedeem.selector);
            redemptionHandler.redeemFromPair(
                address(pair), 
                amountToRedeem, 
                _fee, 
                userToRedeem,
                true // _redeemToUnderlying
            );
            vm.stopPrank();
            return;
        }
        uint256 feePct = redemptionHandler.getRedemptionFeePct(address(pair), amountToRedeem);
        redemptionHandler.redeemFromPair(
            address(pair), 
            amountToRedeem, 
            _fee, 
            userToRedeem,
            true // _redeemToUnderlying
        );
        vm.stopPrank();

        assertApproxEqAbs(
            (amountToRedeem * (PRECISION - feePct)) / PRECISION, // Fee schema
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
        uint256 userCollateralBalanceBefore = pair.userCollateralBalance(user);
        
        vm.startPrank(user);
        pair.removeCollateralVault(
            amountToRemove,
            user
        );
        vm.stopPrank();

        assertEq({
            left: userCollateralBalanceBefore - pair.userCollateralBalance(user),
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
        pair.removeCollateral(
            amountToRemove,
            user
        );
        vm.stopPrank();

        uint256 underlyingToReceive = IERC4626(address(pair.collateral())).previewRedeem(amountToRemove);

        assertEq({
            left: userCollateralBalanceBefore - pair.userCollateralBalance(user),
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
        if (amountToBorrow > pair.totalDebtAvailable()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ResupplyPairConstants.InsufficientDebtAvailable.selector,
                    pair.totalDebtAvailable(),
                    amountToBorrow
                )
            );
            pair.borrow(amountToBorrow, 0, user);
        } else if (amountToBorrow > maxDebtToIssue) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ResupplyPairConstants.Insolvent.selector,
                    amountToBorrow,
                    collat,
                    er
                )
            );
            vm.prank(user);
            pair.borrow(amountToBorrow, 0, user);
        } else if (amountToBorrow < pair.minimumBorrowAmount()) {
            vm.expectRevert(ResupplyPairConstants.InsufficientBorrowAmount.selector);
            pair.borrow(amountToBorrow, 0, user);
        } else {
            vm.prank(user);
            pair.borrow(amountToBorrow, 0, user);
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


    function repayDebtFlow(
        ResupplyPair pair,
        address user,
        uint256 amountToRepay
    ) public {
        uint256 sharesStart = pair.userBorrowShares(user);
        uint256 stableStart = stablecoin.balanceOf(user);
        uint256 stableTsStart = stablecoin.totalSupply();

        vm.startPrank(user);
        stablecoin.approve(address(pair), amountToRepay);
        uint sharesToRepay = pair.toBorrowShares(amountToRepay, false, true);
        console.log(stablecoin.balanceOf(user));
        pair.repay(
            sharesToRepay,
            user
        );
        vm.stopPrank();

        uint256 sharesEnd = pair.userBorrowShares(user);
        uint256 stableEnd = stablecoin.balanceOf(user);
        uint256 stableTsEnd = stablecoin.totalSupply();

        assertEq({
            left: sharesStart - sharesEnd,
            right: sharesToRepay,
            err: "// THEN: Shares not reduced by expected amount"
        });

        assertEq({
            left: stableStart - stableEnd,
            right: amountToRepay,
            err: "// THEN: StableCoin not reduced by expected amount"
        });

        assertEq({
            left: stableTsStart - stableTsEnd,
            right: amountToRepay,
            err: "// THEN: StableCoin TS not reduced by expected amount"
        });
    }

    function liquidationFlow(ResupplyPair pair, address toLiquidate, uint256 er) public {
        (address oracle, ,) = pair.exchangeRateInfo();
        address collateralAddress = address(pair.collateral());
        vm.warp(block.timestamp + 30 days); // NOTICE: ensure pair ingests from oracle
        vm.mockCall(
            oracle,
            abi.encodeWithSignature("getPrices(address)", collateralAddress),
            abi.encode(er)
        );
        pair.addInterest(false);
        uint amountToLiquidate = pair.toBorrowAmount(pair.userBorrowShares(toLiquidate), true, true);
        
        deal(address(stablecoin), address(insurancePool), 10_000e18 + amountToLiquidate, true);

        /// Values to derive state change from
        uint stableTSBefore = stablecoin.totalSupply();
        uint stableBalanceInsuranceBefore = stablecoin.balanceOf(address(insurancePool));
        uint insuracePoolBalanceUnderlyingBefore = pair.underlying().balanceOf(address(insurancePool));
        uint userCollateralBalanceBefore = pair.userCollateralBalance(toLiquidate);
        uint collateralInPairBefore = pair.collateral().balanceOf(address(pair));
        (uint totalBorrowAmountBefore, ) =  pair.totalBorrow();
        uint underlyingExpected = IERC4626(address(pair.collateral())).previewRedeem(userCollateralBalanceBefore);
        uint liquidationIncentive = liquidationHandler.liquidateIncentive();
        liquidationHandler.liquidate(
            address(pair),
            toLiquidate
        );

        (uint totalBorrowAmountAfter, ) =  pair.totalBorrow();
        
        assertEq({
            left: stableTSBefore - stablecoin.totalSupply(),
            right: amountToLiquidate,
            err: "// THEN Stable TS not decremented by expected"
        });
        assertEq({
            left: stableBalanceInsuranceBefore - stablecoin.balanceOf(address(insurancePool)) ,
            right: amountToLiquidate,
            err: "// THEN: insurance pool stable not decremented by expected"
        });
        assertApproxEqAbs(
            pair.underlying().balanceOf(address(insurancePool)) - insuracePoolBalanceUnderlyingBefore + liquidationIncentive,
            underlyingExpected,
            1,
            "// THEN: insurance pool underlying balance not within 1 wei"
        );
        assertEq({
            left: pair.userCollateralBalance(toLiquidate),
            right: 0,
            err: "// THEN: All collateral is not awarded"
        });
        assertEq({
            left: totalBorrowAmountBefore - totalBorrowAmountAfter,
            right: amountToLiquidate,
            err: "// THEN: internal borrow amount not decremented by expected"
        });
    }

}