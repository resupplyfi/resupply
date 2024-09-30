// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "test/e2e/BasePairTest.t.sol";

abstract contract ForkTests is BasePairTest {
    address public alice = address(0x123);
    address public user = address(0xc0ffee);
    address public badActor = address(0xbadbeef);
    address public liquidator = address(0x980);

    bytes public configData_;
    FraxlendPair public fraxlendPair;

    uint256 public start;

    uint256 public ONE_COLLATERAL;

    uint256 public totalAssetSupplied;

    using RateHelper for *;

    function setUp() public virtual {
        run();
        (address _asset, address _collateral, address Oracle, , , , , , ) = abi.decode(
            configData_,
            (address, address, address, uint32, address, uint64, uint256, uint256, uint256)
        );

        ONE_COLLATERAL = 10 ** IERC20_(_collateral).decimals();
        collateral = IERC20(_collateral);
        asset = IERC20(_asset);
        oracle = IDualOracle(Oracle);
    }

    // ============================================================================================
    // Hooks for Child
    // ============================================================================================

    function run() public virtual {}

    function sanityCheckAmountBorrowed(uint256) public virtual {}

    // ============================================================================================
    // Basic function level invariants
    // ============================================================================================

    function testForkDepositUnderlyingToPair() public {
        if (address(collateral) == Constants.Mainnet.SFRAX_ERC20) ONE_COLLATERAL = ONE_COLLATERAL * 1000;
        if (address(collateral) == Constants.Fraxtal.SFRAX_ERC20) ONE_COLLATERAL = ONE_COLLATERAL * 1000;
        if (address(collateral) == Constants.Mainnet.PEPE_ERC20) ONE_COLLATERAL = ONE_COLLATERAL * 1_000_000_000;
        /// @dev Non-compliant ERC20 Tokens
        if (address(collateral) == Constants.Mainnet.LDO_ERC20) {
            vm.prank(0x820fb25352BB0c5E03E07AFc1d86252fFD2F0A18); // LDO WHALE
            collateral.transfer(alice, ONE_COLLATERAL);
        } else {
            deal(address(collateral), alice, ONE_COLLATERAL);
        }
        assertEq(IERC20(collateral).balanceOf(alice), ONE_COLLATERAL);

        vm.startPrank(alice);

        collateral.approve(address(fraxlendPair), ONE_COLLATERAL);
        fraxlendPair.addCollateral(ONE_COLLATERAL, alice);

        assertEq(collateral.balanceOf(alice), 0);
        console.log(fraxlendPair.userCollateralBalance(alice), ONE_COLLATERAL);
        assertEq(fraxlendPair.userCollateralBalance(alice), ONE_COLLATERAL);
        assertEq(collateral.balanceOf(address(fraxlendPair)), ONE_COLLATERAL);
    }

    // function testForkSupplyToLendingPair() public {
    //     if (address(asset) == Constants.Mainnet.WBTC_ERC20) totalAssetSupplied = 0.25e8;
    //     else totalAssetSupplied = 500_000e18;
    //     deal(address(asset), user, totalAssetSupplied);
    //     assertEq(asset.balanceOf(user), totalAssetSupplied);

    //     vm.startPrank(user);
    //     asset.approve(address(fraxlendPair), totalAssetSupplied);
    //     fraxlendPair.deposit(totalAssetSupplied, user);
    //     vm.stopPrank();

    //     assertEq(IERC20(asset).balanceOf(user), 0);
    //     assertEq(fraxlendPair.balanceOf(user), totalAssetSupplied);
    // }

    function testForkBorrowingPowerInvariant() public {
        testForkDepositUnderlyingToPair();
        // testForkSupplyToLendingPair();
        vm.startPrank(alice);
        uint256 maxLtv = fraxlendPair.maxLTV();
        fraxlendPair.updateExchangeRate();
        (, , , uint256 low, uint256 high) = fraxlendPair.exchangeRateInfo();
        if (low != high) {
            bytes memory reversion = abi.encodeWithSelector(
                FraxlendPairConstants.Insolvent.selector,
                (ONE_COLLATERAL * ((maxLtv * 1e18) / LTV_PRECISION)) / low,
                ONE_COLLATERAL,
                high
            );
            vm.expectRevert(reversion);
            fraxlendPair.borrowAsset((ONE_COLLATERAL * (((maxLtv * 1e18) / LTV_PRECISION))) / low, 0, alice);
        } else {
            bytes memory reversion = abi.encodeWithSelector(
                FraxlendPairConstants.Insolvent.selector,
                (ONE_COLLATERAL * (((maxLtv * 1e18) / LTV_PRECISION))) / (low - (low / 10)),
                ONE_COLLATERAL,
                high
            );
            vm.expectRevert(reversion);
            fraxlendPair.borrowAsset(
                (ONE_COLLATERAL * (((maxLtv * 1e18) / LTV_PRECISION))) / (low - (low / 10)),
                0,
                alice
            );
        }
        uint256 borrowAmt = (ONE_COLLATERAL * ((maxLtv * 1e18) / LTV_PRECISION)) / high;
        fraxlendPair.borrowAsset(borrowAmt, 0, alice);
        start = block.timestamp;

        (uint256 totalBorrow, uint256 totalShares) = fraxlendPair.totalBorrow();
        assertEq(asset.balanceOf(alice), borrowAmt);
        assertEq(totalBorrow, borrowAmt);
        assertEq(totalShares, borrowAmt);
        assertEq(asset.balanceOf(address(fraxlendPair)), totalAssetSupplied - borrowAmt);
        console.log("\nThe amount borrowed for one unit collateral: ", borrowAmt);
        sanityCheckAmountBorrowed(borrowAmt);

        /// @notice Check that borrowed amount is less than collateral
        (, uint256 lowER, uint256 highER) = oracle.getPrices();

        uint256 balBorrowed = asset.balanceOf(alice);

        /// @dev Fix: FInd better way to generalize
        if (lowER == highER) return;
        /// @dev If Lido: Chainlink Oracle denominated in ETH -> return
        if (address(collateral) == Constants.Mainnet.LDO_ERC20) return;
        /// @dev Reth Pair uses eth denominated chainlink orace -> return
        if (address(collateral) == Constants.Mainnet.RETH_ERC20) return;
        /// @dev SFRAX Pairs use multiple oracles and do not abstract to code -> return
        if (address(collateral) == Constants.Mainnet.SFRAX_ERC20) return;
        /// @dev ezEth pair uses eth denominated chainlink oracle -> return
        if (address(collateral) == Constants.Mainnet.EZETH_ERC20) return;
        /// @dev ebEth pair uses eth denominated chainlink oracle -> return
        if (address(collateral) == Constants.Mainnet.CBETH_ERC20) return;
        /// @dev sfrxETH pair uses multiple chainlink oracles -> return
        if (address(collateral) == Constants.Arbitrum.SFRXETH_ERC20) return;
        // @dev weEth Pair uses eth denominated chainlink oracle -> return
        if (address(collateral) == Constants.Mainnet.WEETH_ERC20) return;
        // @dev woEth pair uses eth deniminated chainlink oracle -> return
        if (address(collateral) == Constants.Mainnet.WOETH_ERC20) return;
        try IClOralce(address(oracle)).CHAINLINK_FEED_ADDRESS() {
            address clOracle = IClOralce(address(oracle)).CHAINLINK_FEED_ADDRESS();
            uint256 price = uint256(IClOralce(clOracle).latestAnswer()) *
                10 ** (18 - uint256(IClOralce(clOracle).decimals()));
            if (address(collateral) == Constants.Mainnet.WSTETH_ERC20) {
                price = (price * IWstEth(address(collateral)).getStETHByWstETH(1e18)) / 1e18;
            }
            uint256 ltv_cl = (balBorrowed * 1e5) / price;
            if (address(collateral) == Constants.Mainnet.RSETH_ERC20) {
                assertTrue((0.59e5 <= ltv_cl && ltv_cl <= 0.6e5), "LRT: Borrowing Power Invariant Broken");
            } else if (address(collateral) == Constants.Mainnet.MATIC_ERC20) {
                assertTrue((0.64e5 <= ltv_cl && ltv_cl <= 0.65e5), "LRT: Borrowing Power Invariant Broken");
            } else {
                assertTrue((0.73e5 <= ltv_cl && ltv_cl <= 0.75e5), "Borrowing Power Invariant Broken");
            }
        } catch {}
    }

    //TODO, update test
    function testForkDepositAccruesInterest() public {
        testForkBorrowingPowerInvariant();
        (, , , , uint64 fullUtilRate) = fraxlendPair.currentRateInfo();

        /// @notice Interest Math uses prior balances
        (uint256 totalBorrow, ) = fraxlendPair.totalBorrow();
        uint256 borrowLimit = fraxlendPair.borrowLimit();

        vm.warp(block.timestamp + 1 days);
        fraxlendPair.updateExchangeRate();
        printRateInfo();

        fraxlendPair.updateExchangeRate();

        // assertEq(fraxlendPair.balanceOf(user), totalAssetSupplied);
        // assertGt(fraxlendPair.convertToAssets(fraxlendPair.balanceOf(user)), totalAssetSupplied);

        // Assert that the total interest earned is equal to the change in totalAssets:
        (uint256 newRate, ) = IRateCalculatorV2Old(fraxlendPair.rateContract()).getNewRate(
            1 days,
            (1e5 * totalBorrow) / borrowLimit,
            fullUtilRate
        );

        uint256 calcIE = ((1 days * newRate * totalBorrow) / 1e18);
        console.log("The calculated interest is: ", calcIE);
        console.log("The new rate: ", newRate);

        // uint256 totalAssetEnd = fraxlendPair.totalAssets();
        // assertEq(calcIE, totalAssetEnd - totalAssetStart, "All interest must be accounted for");

        printRateInfo();
    }

    // function testForkVaultCanWindDown() public {
    //     testForkBorrowingPowerInvariant();
    //     fraxlendPair.updateExchangeRate();
    //     uint256 sharesOutstandingAlice = fraxlendPair.userBorrowShares(alice);
    //     uint256 debtAlice = fraxlendPair.toBorrowAmount(sharesOutstandingAlice, true, true);
    //     deal(address(asset), alice, debtAlice);

    //     vm.startPrank(alice);
    //     asset.approve(address(fraxlendPair), debtAlice);
    //     fraxlendPair.repayAsset(sharesOutstandingAlice, alice);

    //     // Check that alice has repayed all calculated debt
    //     assertEq(asset.balanceOf(alice), 0);

    //     fraxlendPair.removeCollateral(ONE_COLLATERAL, alice);

    //     // Check that alice is able to withdraw all collateral after repaying debt
    //     assertEq(collateral.balanceOf(alice), ONE_COLLATERAL);
    //     vm.stopPrank();

    //     // console.log(fraxlendPair.balanceOf(user));

    //     uint256 toWithdraw = fraxlendPair.toAssetAmount(fraxlendPair.balanceOf(user), true, true);
    //     vm.prank(user);
    //     fraxlendPair.withdraw(toWithdraw, user, user);
    //     // Asset that the user has withdrawn all shares
    //     assertEq(fraxlendPair.balanceOf(user), 0);
    //     assertEq(asset.balanceOf(user), toWithdraw);
    // }

    function testForkPairCanLiquidateUnderwaterPosition() public {
        testForkBorrowingPowerInvariant();
        // if (
        //     address(collateral) == Constants.Fraxtal.FXB_20291231 ||
        //     address(collateral) == Constants.Fraxtal.FXB_20551231
        // ) {
        //     vm.startPrank(user);
        //     fraxlendPair.withdraw((asset.balanceOf(address(fraxlendPair))), user, user);
        //     fraxlendPair.addInterest(false);
        //     vm.stopPrank();
        // }
        vm.warp(block.timestamp + 10_000 days);

        fraxlendPair.updateExchangeRate();
        deal(address(asset), liquidator, 2_000_000e18);

        (, , , uint256 low, uint256 high) = fraxlendPair.exchangeRateInfo();
        uint256 sharesToLiquidate = fraxlendPair.userBorrowShares(alice) / 20;

        vm.startPrank(liquidator);
        asset.approve(address(fraxlendPair), 2_000_000e18);
        fraxlendPair.liquidate(alice);

        uint256 amtSpent = stdMath.delta(asset.balanceOf(liquidator), 2_000_000e18);
        uint256 amtToLiquidate = fraxlendPair.toBorrowAmount(sharesToLiquidate, false, false);

        // console.log(amtSpent, amtToLiquidate);
        uint256 amtSpot = (amtToLiquidate * low) / 1e18;
        console.log("amtSpot --->", amtSpot, fraxlendPair.liquidationFee());
        uint256 amtSpotDirty = ((1e5 + fraxlendPair.liquidationFee()) * amtSpot) / 1e5;
        console.log("--->", amtSpotDirty);
        uint256 protocolFees = 0;
        uint256 liqPayment = stdMath.delta(protocolFees, amtSpotDirty);

        // Assert that the liquidator receives the calculated payment
        assertEq(liqPayment, collateral.balanceOf(liquidator));

        // Assert that the collateralSeized is w/n 1 wei of the value calculated (Diff due to rounding)
        uint256 collateralSeized = stdMath.delta(fraxlendPair.userCollateralBalance(alice), ONE_COLLATERAL);
        uint256 diff = stdMath.delta(collateralSeized, amtSpotDirty);
        assertLe(diff, 1, "Collateral Seized amount off");
        assertEq(collateralSeized, amtSpotDirty);
    }

    // ============================================================================================
    // Access control level invariants: OnlyTimelock
    // ============================================================================================

    function testForkOnlyTimelockToRevokeOracleInfoSetter() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.revokeOracleInfoSetter();
    }

    function testForkOnlyTimelockToSetOracle() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.setOracle(address(0x456), 0.05 * 1e5);
    }

    function testForkOnlyTimelockToRevokeMaxLTVSetter() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.revokeMaxLTVSetter();
    }

    function testForkOnlyTimelockToSetMaxLTV() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.setMaxLTV(0.85e5);
    }

    function testForkOnlyTimelockToRevokeRateContractSetter() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.revokeRateContractSetter();
    }

    function testForkOnlyTimelockToSetRateContract() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.setRateContract(address(0x456));
    }

    function testForkOnlyTimelockToRevokeLiquidationFeeSetter() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.revokeLiquidationFeeSetter();
    }

    function testForkOnlyTimelockToSetLiquidationFees() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.setLiquidationFees(0.5e5);
    }

    function testForkOnlyTimelockToChangeFee() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.changeFee(0.5e5);
    }

    // function testForkOnlyTimelockRevokeBorrowLimitAC() public {
    //     vm.prank(badActor);
    //     vm.expectRevert(Timelock2Step.OnlyTimelock.selector);
    //     fraxlendPair.revokeBorrowLimitAccessControl(1e18);
    // }

    // function testForkOnlyTimelockRevokeDepositLimitAC() public {
    //     vm.prank(badActor);
    //     vm.expectRevert(Timelock2Step.OnlyTimelock.selector);
    //     fraxlendPair.revokeDepositLimitAccessControl(1e18);
    // }

    function testForkOnlyTimelockRevokeRepayAC() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.revokeRepayAccessControl();
    }

    function testForkOnlyTimelockRevokeWithdrawAC() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.revokeWithdrawAccessControl();
    }

    function testForkOnlyTimelockRevokeLiquidateAC() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.revokeLiquidateAccessControl();
    }

    function testForkOnlyTimelockRevokeInterestAC() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.revokeInterestAccessControl();
    }

    function testForkOnlyTimelockSetBorrowLimit() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.setBorrowLimit(1e18);
    }

    // function testForkOnlyTimelockSetDepositLimit() public {
    //     vm.prank(badActor);
    //     vm.expectRevert(FraxlendPairAccessControlErrors.OnlyTimelockOrOwner.selector);
    //     fraxlendPair.setDepositLimit(1e18);
    // }

    // ============================================================================================
    // Access control level invariants: Only Timelock or Owner
    // ============================================================================================

    function testForkOnlyTimelockOrOwnerUnpause() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.unpause();
    }

    // function testForkOnlyTimelockOrOwnerSetDepositLimit() public {
    //     vm.prank(badActor);
    //     vm.expectRevert(FraxlendPairAccessControlErrors.OnlyTimelockOrOwner.selector);
    //     fraxlendPair.setDepositLimit(100e18);
    // }

    function testForkOnlyTimlockOrOwnerUpause() public isPaused {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.unpause();
    }

    // ============================================================================================
    // Access control level invariants: Only Protocol or Owner
    // ============================================================================================

    function testForkOnlyProtocolOrOwnerPause() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.pause();
    }

    function testForkOnlyProtocolOrOwnerPauseRepay() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.pauseRepay(true);
    }

    function testForkOnlyProtocolOrOwnerPauseWithdraw() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.pauseWithdraw(true);
    }

    function testForkOnlyProtocolOrOwnerPauseLiquidate() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.pauseLiquidate(true);
    }

    function testForkOnlyProtocolOrOwnerPauseInterest() public {
        vm.prank(badActor);
        vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
        fraxlendPair.pauseInterest(true);
    }

    // function testForkOnlyProtocolOrOwnerPauseDeposit() public {
    //     vm.prank(badActor);
    //     vm.expectRevert(FraxlendPairAccessControlErrors.OnlyProtocolOrOwner.selector);
    //     fraxlendPair.pauseDeposit();
    // }

    // ============================================================================================
    // Assert Paused State Functionality
    // ============================================================================================

    /// @notice Asset Deposit is paused
    // function testForkPausedDisallowAssetDeposit() public isPaused {
    //     deal(address(asset), user, 1e18);
    //     vm.startPrank(user);
    //     asset.approve(address(fraxlendPair), 1e18);

    //     vm.expectRevert(FraxlendPairAccessControlErrors.ExceedsDepositLimit.selector);
    //     fraxlendPair.deposit(1e18, user);
    // }

    /// @notice Test Borrowing is paused
    function testForkPausedDisAllowBorrow() public {
        // testForkSupplyToLendingPair();
        pausePair();
        /// @notice Add Collateral is not paused
        testForkDepositUnderlyingToPair();
        vm.expectRevert(FraxlendPairAccessControlErrors.ExceedsBorrowLimit.selector);
        fraxlendPair.borrowAsset(1, 0, alice);
    }

    /// @notice Test Asset Withdrawal Paused
    // function testForkPausedDisallowAssetWithdrawal() public {
    //     testForkSupplyToLendingPair();
    //     pausePair();

    //     uint256 toWithdraw = fraxlendPair.toAssetAmount(fraxlendPair.balanceOf(user), true, true);
    //     vm.expectRevert(FraxlendPairAccessControlErrors.WithdrawPaused.selector);
    //     vm.prank(user);
    //     fraxlendPair.withdraw(toWithdraw, user, user);
    // }

    /// @notice Test borrow repayment paused
    function testForkPausedRepayBorrow() public {
        testForkBorrowingPowerInvariant();

        pausePair();

        uint256 sharesOutstandingAlice = fraxlendPair.userBorrowShares(alice);
        uint256 debtAlice = fraxlendPair.toBorrowAmount(sharesOutstandingAlice, true, true);
        deal(address(asset), alice, debtAlice);
        vm.startPrank(alice);
        asset.approve(address(fraxlendPair), debtAlice);

        vm.expectRevert(FraxlendPairAccessControlErrors.RepayPaused.selector);
        fraxlendPair.repayAsset(sharesOutstandingAlice, alice);
    }

    /// @notice Test Liquidation paused
    function testForkPausedLiquidation() public {
        testForkBorrowingPowerInvariant();

        vm.warp(block.timestamp + 10_000 days);
        fraxlendPair.updateExchangeRate();
        deal(address(asset), liquidator, 2_000_000e18);

        (, , , uint256 low, uint256 high) = fraxlendPair.exchangeRateInfo();
        uint256 sharesToLiquidate = fraxlendPair.userBorrowShares(alice) / 20;

        pausePair();

        vm.startPrank(liquidator);
        asset.approve(address(fraxlendPair), 2_000_000e18);

        vm.expectRevert(FraxlendPairAccessControlErrors.LiquidatePaused.selector);
        fraxlendPair.liquidate(alice);
    }

    /// @notice Test interest accrual paused
    function testForkPausedInterestAccrual() public {
        testForkBorrowingPowerInvariant();
        (uint256 totalBorrowStart, ) = fraxlendPair.totalBorrow();

        pausePair();

        vm.warp(block.timestamp + 10_000 days);
        fraxlendPair.addInterest(false);
        (uint256 totalBorrowEnd, ) = fraxlendPair.totalBorrow();
        assertEq(totalBorrowStart, totalBorrowEnd, "Interst is still being accrued");
    }

    function testForkUnpauseOwner() public isPaused {
        vm.prank(fraxlendPair.registry());
        fraxlendPair.unpause();

        bool interestPaused = fraxlendPair.isInterestPaused();
        bool liquidationPaused = fraxlendPair.isLiquidatePaused();
        bool repaymentPaused = fraxlendPair.isRepayPaused();
        bool withdrawalPaused = fraxlendPair.isWithdrawPaused();
        // uint256 depositLimit = fraxlendPair.depositLimit();

        assertFalse(interestPaused, "Interest was not paused");
        assertFalse(liquidationPaused, "Liquidations were not paused");
        assertFalse(repaymentPaused, "Repayments were not paused");
        assertFalse(withdrawalPaused, "Withdrawals were not paused");
        // assertEq(depositLimit, type(uint256).max, "Asset Deposits were not paused");
    }

    function testForkUnpauseTimeLock() public isPaused {
        vm.prank(fraxlendPair.registry());
        fraxlendPair.unpause();

        bool interestPaused = fraxlendPair.isInterestPaused();
        bool liquidationPaused = fraxlendPair.isLiquidatePaused();
        bool repaymentPaused = fraxlendPair.isRepayPaused();
        bool withdrawalPaused = fraxlendPair.isWithdrawPaused();
        // uint256 depositLimit = fraxlendPair.depositLimit();

        assertFalse(interestPaused, "Interest was not paused");
        assertFalse(liquidationPaused, "Liquidations were not paused");
        assertFalse(repaymentPaused, "Repayments were not paused");
        assertFalse(withdrawalPaused, "Withdrawals were not paused");
        // assertEq(depositLimit, type(uint256).max, "Asset Deposits were not paused");
    }

    function pausePair() public {
        vm.startPrank(fraxlendPair.registry());
        fraxlendPair.pause();
        vm.stopPrank();

        bool interestPaused = fraxlendPair.isInterestPaused();
        bool liquidationPaused = fraxlendPair.isLiquidatePaused();
        bool repaymentPaused = fraxlendPair.isRepayPaused();
        bool withdrawalPaused = fraxlendPair.isWithdrawPaused();
        // uint256 depositLimit = fraxlendPair.depositLimit();

        assertTrue(interestPaused, "Interest was not paused");
        assertTrue(liquidationPaused, "Liquidations were not paused");
        assertTrue(repaymentPaused, "Repayments were not paused");
        assertTrue(withdrawalPaused, "Withdrawals were not paused");
        // assertEq(depositLimit, 0, "Asset Deposits were not paused");
    }

    modifier isPaused() {
        pausePair();
        _;
    }

    // ============================================================================================
    // Assert Admin Roles Granted Correctly
    // ============================================================================================
    function testForkRegistrySetCorrectly() public {
        assertEq(getRegistry(), fraxlendPair.registry(), "Registry address does not match expected!");
    }

    // function testForkComptrollerSetCorrectly() public {
    //     assertEq(getComptroller(), fraxlendPair.owner(), "Comptroller address does not match expected!");
    // }

    // function testFormCircuitBreakerSetCorrectly() public {
    //     assertEq(getCircuitBreaker(), fraxlendPair.circuitBreakerAddress(), "CircuitBreaker does not match expected!");
    // }

    // ============================================================================================
    // Assert Timelock is correct
    // ============================================================================================
    function testForkVariableRateRounding(uint16 _deltaTime, uint32 Utilization, uint64 OldFullUtilizationRate) public {
        OldFullUtilizationRate = uint64(
            bound(
                OldFullUtilizationRate,
                uint256(VariableInterestRate(address(fraxlendPair.rateContract())).MIN_FULL_UTIL_RATE()),
                uint256(VariableInterestRate(address(fraxlendPair.rateContract())).MAX_FULL_UTIL_RATE())
            )
        );
        VariableInterestRate variableRateContract = VariableInterestRate(address(fraxlendPair.rateContract()));
        (uint256 _newRate, uint256 _newMaxRate) = variableRateContract.getNewRate(
            _deltaTime,
            Utilization,
            OldFullUtilizationRate
        );

        (uint64 _expectedRate, uint64 _expectedMaxRate) = variableRateContract.__interestCalculator(
            _deltaTime,
            Utilization,
            OldFullUtilizationRate,
            vm
        );
        assertApproxEqRel(uint256(_expectedRate), uint256(_newRate), 1e16);
        assertApproxEqRel(uint256(_expectedMaxRate), uint256(_newMaxRate), 1e16);
    }

    function printRateInfo() public {
        console.log("\n ---- RATE INFO -----");
        (uint256 totalBorrow, uint256 totalShares) = fraxlendPair.totalBorrow();
        uint256 borrowLimit = fraxlendPair.borrowLimit();
        console.log("       The total borrow: ", totalBorrow);
        console.log("       The borrow limit: ", borrowLimit);
        uint256 util = (1e5 * totalBorrow) / borrowLimit;
        console.log("       The utilization: ", util);

        (
            uint32 lastBlock,
            uint32 feeToProtocolRate,
            uint64 lastTimestamp,
            uint64 ratePerSec,
            uint64 fullUtilRate
        ) = fraxlendPair.currentRateInfo();

        console.log("       The rate per seond is: ", ratePerSec);
        console.log("       The full util rate: ", fullUtilRate);
        console.log("       The feeToProtocolRate: ", feeToProtocolRate);
        console.log("       The  lastBlock:", lastBlock);
        console.log("       The lastTimestamp:", lastTimestamp);
    }

    function getRegistry() public view returns (address timelock) {
        if (block.chainid == 1) timelock = Constants.Mainnet.FRAXLEND_PAIR_REGISTRY_ADDRESS;
        if (block.chainid == 42_161) timelock = Constants.Arbitrum.FRAXLEND_PAIR_REGISTRY_ADDRESS;
        if (block.chainid == 252) timelock = Constants.Fraxtal.FRAXLEND_PAIR_REGISTRY_ADDRESS;
    }

    // function getCircuitBreaker() public view returns (address circuitBreaker) {
    //     if (block.chainid == 1) circuitBreaker = Constants.Mainnet.CIRCUIT_BREAKER_ADDRESS;
    //     if (block.chainid == 42_161) circuitBreaker = Constants.Arbitrum.CIRCUIT_BREAKER_ADDRESS;
    //     if (block.chainid == 252) circuitBreaker = Constants.Fraxtal.CIRCUIT_BREAKER_ADDRESS;
    // }

    // function getComptroller() public view returns (address comptroller) {
    //     if (block.chainid == 1) comptroller = Constants.Mainnet.COMPTROLLER_ADDRESS;
    //     if (block.chainid == 42_161) comptroller = Constants.Arbitrum.COMPTROLLER_ADDRESS;
    //     if (block.chainid == 252) comptroller = Constants.Fraxtal.COMPTROLLER_ADDRESS;
    // }
}

// TODO: Assert Reversions of admin specific functions
interface IClOralce {
    function decimals() external returns (uint8);

    function latestAnswer() external returns (int256);

    function CHAINLINK_FEED_ADDRESS() external returns (address);
}

interface IERC20_ is IERC20 {
    function decimals() external view returns (uint8);
}
