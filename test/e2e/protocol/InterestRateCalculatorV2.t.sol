// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "lib/forge-std/src/Test.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";
import { IStakedFrax } from "src/interfaces/frax/IStakedFrax.sol";

contract InterestRateCalculatorV2Test is Test {
    address internal constant SFRXUSD = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;

    MockErc4626Vault internal vault;
    MockPriceWatcher internal priceWatcher;
    InterestRateCalculatorV2 internal calculator;
    PairRateHarness internal pair;

    function setUp() public {
        vault = new MockErc4626Vault();
        priceWatcher = new MockPriceWatcher();
        calculator = new InterestRateCalculatorV2(address(this), 0, 0.5e18, 0.625e18, 0.2e18, address(priceWatcher));
        pair = new PairRateHarness(address(calculator), address(vault));
        _mockSfrxusdRate(0);
    }

    function test_GetNewRateReturnsCurrentVaultShares() public {
        vault.setSharePrice(1.25e18);

        uint256 expectedShares = vault.convertToShares(1e18);
        vm.prank(address(pair));
        (, uint128 newShares) = calculator.getNewRate(address(vault), 1 days, 1e18);

        assertEq(newShares, expectedShares, "new shares should be current vault shares");
        assertGt(newShares, 0, "new shares should never be clobbered to zero");
    }

    function testFuzz_GetNewRateReturnsCurrentVaultShares(uint256 sharePrice) public {
        sharePrice = bound(sharePrice, 0.1e18, 10e18);
        vault.setSharePrice(sharePrice);

        uint256 expectedShares = vault.convertToShares(1e18);
        vm.prank(address(pair));
        (, uint128 newShares) = calculator.getNewRate(address(vault), 1 days, 1e18);

        assertEq(newShares, expectedShares, "new shares should match vault conversion");
        assertGt(newShares, 0, "new shares should remain nonzero");
    }

    function test_PairStoresCurrentVaultSharesAfterAccrual() public {
        skip(1 days);
        vault.setSharePrice(1.1e18);
        pair.addInterest();

        (,, uint128 lastShares) = pair.currentRateInfo();
        assertEq(lastShares, vault.convertToShares(1e18), "first accrual stored wrong shares");
        assertGt(lastShares, 0, "first accrual stored zero shares");

        skip(1 days);
        vault.setSharePrice(1.2e18);
        pair.addInterest();

        (,, lastShares) = pair.currentRateInfo();
        assertEq(lastShares, vault.convertToShares(1e18), "second accrual stored wrong shares");
        assertGt(lastShares, 0, "second accrual stored zero shares");
    }

    function test_SecondAccrualUsesStoredSharesToCaptureVaultYield() public {
        skip(1 days);
        vault.setSharePrice(1.1e18);
        uint64 firstRate = pair.addInterest();
        assertGt(firstRate, 0, "first accrual should see positive vault yield");

        (,, uint128 firstStoredShares) = pair.currentRateInfo();
        skip(1 days);
        vault.setSharePrice(1.21e18);

        uint256 underlyingRate = (vault.convertToAssets(firstStoredShares) - 1e18) / 1 days;
        uint256 expectedRate = calculator.getPairRateWithUnderlying(address(pair), underlyingRate);
        uint64 secondRate = pair.addInterest();

        assertGt(secondRate, 0, "second accrual should still see positive vault yield");
        assertEq(secondRate, expectedRate, "second accrual should use stored shares as baseline");
    }

    function _mockSfrxusdRate(uint256 ratePerSecond) internal {
        vm.etch(SFRXUSD, hex"00");

        IStakedFrax.RewardsCycleData memory rewardsCycleData = IStakedFrax.RewardsCycleData({ cycleEnd: uint40(block.timestamp + 1 days), lastSync: uint40(block.timestamp), rewardCycleAmount: uint216(ratePerSecond * 1 days) });

        vm.mockCall(SFRXUSD, abi.encodeWithSelector(IStakedFrax.rewardsCycleData.selector), abi.encode(rewardsCycleData));
        vm.mockCall(SFRXUSD, abi.encodeWithSelector(IStakedFrax.storedTotalAssets.selector), abi.encode(1e18));
        vm.mockCall(SFRXUSD, abi.encodeWithSelector(IStakedFrax.maxDistributionPerSecondPerAsset.selector), abi.encode(type(uint256).max));
    }
}

contract PairRateHarness {
    struct CurrentRateInfo {
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint128 lastShares;
    }

    InterestRateCalculatorV2 public immutable calculator;
    MockErc4626Vault public immutable collateral;
    CurrentRateInfo public currentRateInfo;

    constructor(address _calculator, address _collateral) {
        calculator = InterestRateCalculatorV2(_calculator);
        collateral = MockErc4626Vault(_collateral);
        currentRateInfo = CurrentRateInfo({ lastTimestamp: uint64(block.timestamp), ratePerSec: 0, lastShares: uint128(collateral.convertToShares(1e18)) });
    }

    function addInterest() external returns (uint64 newRate) {
        CurrentRateInfo memory info = currentRateInfo;
        (newRate, info.lastShares) = calculator.getNewRate(address(collateral), block.timestamp - info.lastTimestamp, info.lastShares);
        info.ratePerSec = newRate;
        info.lastTimestamp = uint64(block.timestamp);
        currentRateInfo = info;
    }
}

contract MockErc4626Vault {
    uint256 public sharePrice = 1e18;

    function setSharePrice(uint256 _sharePrice) external {
        sharePrice = _sharePrice;
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        return assets * 1e18 / sharePrice;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares * sharePrice / 1e18;
    }
}

contract MockPriceWatcher {
    uint256 public weight;

    function setWeight(uint256 _weight) external {
        weight = _weight;
    }

    function findPairPriceWeight(address) external view returns (uint256) {
        return weight;
    }
}
