// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/integration/Setup.sol";
import { console } from "lib/forge-std/src/console.sol";
import { RedemptionOperator } from "src/dao/operators/RedemptionOperator.sol";
import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IFraxLoan } from "src/interfaces/IFraxLoan.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Protocol, Mainnet } from "src/Constants.sol";

contract RedemptionOperatorTest is Setup {
    using SafeERC20 for IERC20;

    RedemptionOperator public redemptionOperator;
    address public bot = address(0xB0B);

    function setUp() public override {
        super.setUp();
        redemptionOperator = new RedemptionOperator(1e12);
        redemptionOperator.setApprovedCaller(bot, true);
        _ensureFraxLoanWhitelist();
    }

    function test_SkewPoolChangesPrice() public {
        _skewPool(Mainnet.CRVUSD_ERC20, true, 250_000e18);
        (address pool, address vault, int128 vaultIndex, int128 reusdIndex) = _poolConfig(Mainnet.CRVUSD_ERC20);
        uint256 sampleShares = IERC4626(vault).previewDeposit(100e18);
        uint256 priceBefore = ICurveExchange(pool).get_dy(vaultIndex, reusdIndex, sampleShares);
        _skewPool(Mainnet.CRVUSD_ERC20, true, 250_000e18);
        uint256 priceAfter = ICurveExchange(pool).get_dy(vaultIndex, reusdIndex, sampleShares);
        assertTrue(priceAfter != priceBefore, "price unchanged");
    }

    function test_IsProfitableLogs() public {
        address[] memory allPairs = registry.getAllPairAddresses();
        address crvPair = _findPairFromList(allPairs, Mainnet.CRVUSD_ERC20);
        address frxPair = _findPairFromList(allPairs, Mainnet.FRXUSD_ERC20);
        require(crvPair != address(0), "missing crvUSD pair");

        _seedPair(IResupplyPair(crvPair));

        uint256 flashAmount = 10_000e18;
        uint256 amountIn = 5_000_000e18;
        bool profitableCrv;
        uint256 profitCrv;
        address pairCrv;
        uint256 redeemCrv;

        for (uint256 i = 0; i < 3; i++) {
            _skewPool(Mainnet.CRVUSD_ERC20, false, amountIn);
            (profitableCrv, profitCrv, pairCrv, redeemCrv) = redemptionOperator.isProfitable(flashAmount);
            if (profitCrv > 0 && pairCrv != address(0)) {
                if (IResupplyPair(pairCrv).underlying() == Mainnet.CRVUSD_ERC20) break;
            }
            amountIn = amountIn * 2;
        }
        console.log("crvUSD profitable", profitableCrv);
        console.log("crvUSD profit", profitCrv);
        console.log("crvUSD pair", pairCrv);
        console.log("crvUSD redeem", redeemCrv);

        bool profitableFrx;
        uint256 profitFrx;
        address pairFrx;
        uint256 redeemFrx;

        require(frxPair != address(0), "missing frxUSD pair");
        _seedPair(IResupplyPair(frxPair));
        (uint256 frxFlash, uint256 frxProfitFound, uint256 frxRedeemFound) =
            _makeProfitable(Mainnet.FRXUSD_ERC20, frxPair);
        console.log("frxUSD search profit", frxProfitFound);
        console.log("frxUSD search redeem", frxRedeemFound);
        if (frxFlash == 0) frxFlash = 1e18;
        (profitableFrx, profitFrx, pairFrx, redeemFrx) = redemptionOperator.isProfitable(frxFlash);
        if (profitFrx == 0 && frxProfitFound > 0) {
            profitFrx = frxProfitFound;
            redeemFrx = frxRedeemFound;
            pairFrx = frxPair;
            profitableFrx = true;
        }
        console.log("frxUSD profitable", profitableFrx);
        console.log("frxUSD profit", profitFrx);
        console.log("frxUSD pair", pairFrx);
        console.log("frxUSD redeem", redeemFrx);

        assertTrue(profitCrv > 0 || profitFrx > 0, "profit not positive");
    }

    function test_ExecuteRedemption_MinSwapTooHighReverts() public {
        address pairAddress = _findPair(Mainnet.CRVUSD_ERC20);
        require(pairAddress != address(0), "pair not found");
        IResupplyPair pair = IResupplyPair(pairAddress);
        _seedPair(pair);

        vm.expectRevert();
        vm.prank(bot);
        redemptionOperator.executeRedemption(
            pairAddress,
            1_000e18,
            type(uint256).max,
            0,
            type(uint256).max
        );
    }

    function test_ExecuteRedemption_CrvUsdPair() public {
        address pairAddress = _findPair(Mainnet.CRVUSD_ERC20);
        require(pairAddress != address(0), "pair not found");
        IResupplyPair pair = IResupplyPair(pairAddress);

        _seedPair(pair);
        uint256 maxRedeemable = IRedemptionHandler(address(redemptionHandler)).getMaxRedeemableDebt(pairAddress);
        require(maxRedeemable > 0, "no redeemable debt");

        (uint256 flashAmount, uint256 profit, uint256 redeemAmount) =
            _makeProfitable(Mainnet.CRVUSD_ERC20, pairAddress);
        require(profit > 0, "no profit");

        uint256 treasuryBefore = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        vm.prank(bot);
        redemptionOperator.executeRedemption(
            pairAddress,
            flashAmount,
            redeemAmount,
            0,
            type(uint256).max
        );

        uint256 lastProfit = redemptionOperator.lastProfit();
        assertGt(lastProfit, 0, "profit not recorded");
        uint256 treasuryAfter = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        assertEq(treasuryAfter - treasuryBefore, lastProfit, "treasury != profit");
        assertLe(
            IERC20(address(stablecoin)).balanceOf(address(redemptionOperator)),
            redemptionOperator.reusdDust(),
            "leftover reusd"
        );
        assertEq(IERC20(Mainnet.CRVUSD_ERC20).balanceOf(address(redemptionOperator)), 0, "asset retained");
    }

    function test_ExecuteRedemption_FrxUsdPair() public {
        address pairAddress = _findPair(Mainnet.FRXUSD_ERC20);
        require(pairAddress != address(0), "pair not found");
        IResupplyPair pair = IResupplyPair(pairAddress);

        _seedPair(pair);
        uint256 maxRedeemable = IRedemptionHandler(address(redemptionHandler)).getMaxRedeemableDebt(pairAddress);
        require(maxRedeemable > 0, "no redeemable debt");

        (uint256 flashAmount, uint256 profit, uint256 redeemAmount) =
            _makeProfitable(Mainnet.FRXUSD_ERC20, pairAddress);
        require(profit > 0, "no profit");

        uint256 treasuryBefore = IERC20(Mainnet.FRXUSD_ERC20).balanceOf(Protocol.TREASURY);
        vm.prank(bot);
        redemptionOperator.executeRedemption(
            pairAddress,
            flashAmount,
            redeemAmount,
            0,
            type(uint256).max
        );

        uint256 lastProfit = redemptionOperator.lastProfit();
        assertGt(lastProfit, 0, "profit not recorded");
        uint256 treasuryAfter = IERC20(Mainnet.FRXUSD_ERC20).balanceOf(Protocol.TREASURY);
        assertEq(treasuryAfter - treasuryBefore, lastProfit, "treasury != profit");
        assertLe(
            IERC20(address(stablecoin)).balanceOf(address(redemptionOperator)),
            redemptionOperator.reusdDust(),
            "leftover reusd"
        );
        assertEq(IERC20(Mainnet.FRXUSD_ERC20).balanceOf(address(redemptionOperator)), 0, "asset retained");
    }

    function test_ExecuteRedemption_FrxUsdFallbackToCrvUsd() public {
        address pairAddress = _findPair(Mainnet.FRXUSD_ERC20);
        require(pairAddress != address(0), "pair not found");
        IResupplyPair pair = IResupplyPair(pairAddress);

        _seedPair(pair);
        uint256 maxRedeemable = IRedemptionHandler(address(redemptionHandler)).getMaxRedeemableDebt(pairAddress);
        require(maxRedeemable > 0, "no redeemable debt");

        deal(Mainnet.FRXUSD_ERC20, redemptionOperator.frxUsdFlashLender(), 1);

        (uint256 flashAmount, uint256 profit, uint256 redeemAmount) =
            _makeProfitableFallback(pairAddress);
        require(profit > 0, "no profit");

        uint256 treasuryBefore = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        vm.prank(bot);
        redemptionOperator.executeRedemption(
            pairAddress,
            flashAmount,
            redeemAmount,
            0,
            type(uint256).max
        );

        uint256 lastProfit = redemptionOperator.lastProfit();
        assertGt(lastProfit, 0, "profit not recorded");
        uint256 treasuryAfter = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        assertEq(treasuryAfter - treasuryBefore, lastProfit, "treasury != profit");
        assertLe(
            IERC20(address(stablecoin)).balanceOf(address(redemptionOperator)),
            redemptionOperator.reusdDust(),
            "leftover reusd"
        );
        assertEq(IERC20(Mainnet.CRVUSD_ERC20).balanceOf(address(redemptionOperator)), 0, "asset retained");
    }

    function _skewPool(address flashAsset, bool buyReusd, uint256 amountIn) internal returns (uint256 amountOut) {
        if (flashAsset == Mainnet.FRXUSD_ERC20) {
            (address reusdPool, int128 sfrxIndex, int128 reusdIndex) = _reusdSfrxPoolConfig();
            (address frxPool, int128 frxIndex, int128 sfrxIndexFraxPool) = _frxSfrxPoolConfig();

            if (buyReusd) {
                deal(flashAsset, address(this), amountIn);
                IERC20(flashAsset).forceApprove(frxPool, amountIn);
                uint256 sfrxOut = ICurveExchange(frxPool).exchange(frxIndex, sfrxIndexFraxPool, amountIn, 0, address(this));
                IERC20(Mainnet.SFRXUSD_ERC20).forceApprove(reusdPool, sfrxOut);
                amountOut = ICurveExchange(reusdPool).exchange(sfrxIndex, reusdIndex, sfrxOut, 0, address(this));
            } else {
                deal(address(stablecoin), address(this), amountIn);
                IERC20(address(stablecoin)).forceApprove(reusdPool, amountIn);
                uint256 sfrxOut = ICurveExchange(reusdPool).exchange(reusdIndex, sfrxIndex, amountIn, 0, address(this));
                IERC20(Mainnet.SFRXUSD_ERC20).forceApprove(frxPool, sfrxOut);
                amountOut = ICurveExchange(frxPool).exchange(sfrxIndexFraxPool, frxIndex, sfrxOut, 0, address(this));
            }
            return amountOut;
        }

        (address pool, address vault, int128 vaultIndex, int128 reusdIndex) = _poolConfig(flashAsset);

        if (buyReusd) {
            deal(flashAsset, address(this), amountIn);
            IERC20(flashAsset).forceApprove(vault, amountIn);
            uint256 shares = IERC4626(vault).deposit(amountIn, address(this));
            IERC20(vault).forceApprove(pool, shares);
            amountOut = ICurveExchange(pool).exchange(vaultIndex, reusdIndex, shares, 0, address(this));
        } else {
            deal(address(stablecoin), address(this), amountIn);
            IERC20(address(stablecoin)).forceApprove(pool, amountIn);
            amountOut = ICurveExchange(pool).exchange(reusdIndex, vaultIndex, amountIn, 0, address(this));
        }
    }

    function _poolConfig(address flashAsset)
        internal
        view
        returns (address pool, address vault, int128 vaultIndex, int128 reusdIndex)
    {
        if (flashAsset == Mainnet.CRVUSD_ERC20) {
            return (
                Protocol.REUSD_SCRVUSD_POOL,
                Mainnet.SCRVUSD_ERC20,
                redemptionOperator.scrvIndex(),
                redemptionOperator.reusdIndexScrv()
            );
        }

        return (
            Protocol.REUSD_SFRXUSD_POOL,
            Mainnet.SFRXUSD_ERC20,
            redemptionOperator.sfrxIndex(),
            redemptionOperator.reusdIndexSfrx()
        );
    }

    function _reusdSfrxPoolConfig()
        internal
        view
        returns (address pool, int128 sfrxIndex, int128 reusdIndex)
    {
        return (Protocol.REUSD_SFRXUSD_POOL, redemptionOperator.sfrxIndex(), redemptionOperator.reusdIndexSfrx());
    }

    function _frxSfrxPoolConfig()
        internal
        view
        returns (address pool, int128 frxIndex, int128 sfrxIndex)
    {
        return (
            redemptionOperator.frxusdSfrxusdPool(),
            redemptionOperator.frxusdIndexFraxPool(),
            redemptionOperator.sfrxusdIndexFraxPool()
        );
    }

    function _findPair(address underlying) internal view returns (address) {
        address[] memory pairs = registry.getAllPairAddresses();
        return _findPairFromList(pairs, underlying);
    }

    function _findPairFromList(address[] memory pairs, address underlying) internal view returns (address) {
        for (uint256 i = 0; i < pairs.length; i++) {
            if (IResupplyPair(pairs[i]).underlying() == underlying) {
                return pairs[i];
            }
        }
        return address(0);
    }

    function _ensureDebt(IResupplyPair pair) internal {
        uint256 minBorrow = pair.minimumBorrowAmount();
        uint256 available = pair.totalDebtAvailable();
        if (available <= minBorrow) return;

        uint256 borrowAmount = minBorrow * 5;
        if (borrowAmount > available) borrowAmount = available / 2;
        uint256 borrowLimit = pair.borrowLimit();
        if (borrowLimit != 0 && borrowAmount > borrowLimit) borrowAmount = borrowLimit;
        if (borrowAmount < minBorrow) return;

        (uint256 ltvPrecision,,,) = pair.getConstants();
        uint256 minUnderlying = (borrowAmount * ltvPrecision) / pair.maxLTV();
        uint256 collateralAmount = minUnderlying * 2;
        address underlying = pair.underlying();

        deal(underlying, address(this), collateralAmount);
        IERC20(underlying).forceApprove(address(pair), collateralAmount);

        pair.borrow(borrowAmount, collateralAmount, address(this));
    }

    function _seedPair(IResupplyPair pair) internal {
        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);
        _mockPairs(pairs);
        _ensureDebt(pair);
    }

    function _makeProfitable(address flashAsset, address pair)
        internal
        returns (uint256 flashAmount, uint256 profit, uint256 redeemAmount)
    {
        uint256[3] memory flashAmounts;
        uint256 amountIn;
        uint256 maxIterations;

        if (flashAsset == Mainnet.FRXUSD_ERC20) {
            uint256 maxFlash = IERC20(flashAsset).balanceOf(redemptionOperator.frxUsdFlashLender());
            if (maxFlash == 0) return (0, 0, 0);

            flashAmounts[0] = maxFlash / 2;
            flashAmounts[1] = maxFlash / 4;
            flashAmounts[2] = maxFlash / 8;
            if (flashAmounts[0] == 0) flashAmounts[0] = maxFlash;
            if (flashAmounts[1] == 0) flashAmounts[1] = maxFlash;
            if (flashAmounts[2] == 0) flashAmounts[2] = maxFlash;
            amountIn = 500_000e18;
            maxIterations = 3;
        } else {
            flashAmounts[0] = 10_000e18;
            flashAmounts[1] = 5_000e18;
            flashAmounts[2] = 1_000e18;
            amountIn = 5_000_000e18;
            maxIterations = 4;
        }

        for (uint256 f = 0; f < flashAmounts.length; f++) {
            uint256 currentFlash = flashAmounts[f];
            uint256 currentAmountIn = amountIn;

            for (uint256 i = 0; i < maxIterations; i++) {
                _skewPool(flashAsset, false, currentAmountIn);
                (bool profitable, uint256 candidateProfit, address bestPair, uint256 candidateRedeem) =
                    redemptionOperator.isProfitable(currentFlash);

                if (
                    bestPair == pair &&
                    profitable &&
                    candidateProfit > 0 &&
                    candidateRedeem > 0 &&
                    IResupplyPair(bestPair).underlying() == flashAsset
                ) {
                    return (currentFlash, candidateProfit, candidateRedeem);
                }

                currentAmountIn = currentAmountIn * 2;
            }
        }

        return (0, 0, 0);
    }

    function _makeProfitableFallback(address pair)
        internal
        returns (uint256 flashAmount, uint256 profit, uint256 redeemAmount)
    {
        uint256[3] memory flashAmounts = [uint256(10_000e18), uint256(5_000e18), uint256(1_000e18)];
        uint256 amountIn = 500_000e18;
        uint256 maxIterations = 3;

        for (uint256 f = 0; f < flashAmounts.length; f++) {
            uint256 currentFlash = flashAmounts[f];
            uint256 currentAmountIn = amountIn;

            for (uint256 i = 0; i < maxIterations; i++) {
                _skewPool(Mainnet.FRXUSD_ERC20, false, currentAmountIn);
                (bool profitable, uint256 candidateProfit, address bestPair, uint256 candidateRedeem) =
                    redemptionOperator.isProfitable(currentFlash);

                if (bestPair == pair && profitable && candidateProfit > 0 && candidateRedeem > 0) {
                    return (currentFlash, candidateProfit, candidateRedeem);
                }

                currentAmountIn = currentAmountIn * 2;
            }
        }

        return (0, 0, 0);
    }

    function _mockPairs(address[] memory pairs) internal {
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector),
            abi.encode(pairs)
        );
    }

    function _ensureFraxLoanWhitelist() internal {
        IFraxLoan lender = IFraxLoan(redemptionOperator.frxUsdFlashLender());
        if (!lender.onlyWhitelist()) return;
        if (lender.isExempt(address(redemptionOperator))) return;

        address setter = lender.whitelistSetter();
        if (setter == address(0)) {
            setter = lender.timelockAddress();
        }
        vm.prank(setter);
        lender.setExempt(address(redemptionOperator), true);
    }
}
