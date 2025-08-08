// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.30;

import { Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { SavingsReUSD } from "src/protocol/sreusd/sreUSD.sol";
import { ERC20, LinearRewardsErc4626 } from "src/protocol/sreusd/LinearRewardsErc4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/e2e/Setup.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { FeeLogger } from "src/protocol/FeeLogger.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";

import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { IRewardHandler } from "src/interfaces/IRewardHandler.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";

contract SreUSDTest is Setup {
    SavingsReUSD public vault;
    IERC20 public asset;

    uint32 public constant REWARDS_CYCLE_LENGTH = 7 days;
    uint256 public constant MAX_DISTRIBUTION_PER_SECOND_PER_ASSET = 1e18;
    address[] public pairs;

    function setUp() public override {
        super.setUp();
        asset = IERC20(address(stablecoin));
        vault = stakedStable;
        deal(address(govToken), address(user1), 1000e18);
        _makeInitialGovStakerDeposit();
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function test_Initialization() public {
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.name(), "Staked reUSD");
        assertEq(vault.symbol(), "sreUSD");
        assertEq(vault.owner(), address(core));
    }

    function test_Deposit(uint256 amount) public {
        amount = bound(amount, 1, 1000e18);
        uint256 shares = deposit(address(this), amount);
        assertEq(vault.balanceOf(address(this)), shares);
        assertEq(asset.balanceOf(address(vault)), amount);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.totalSupply(), shares);
    }

    function test_Withdraw(uint256 amount) public {
        amount = bound(amount, 1, 1000e18);
        uint256 shares = deposit(address(this), amount);
        uint256 withdrawn = vault.withdraw(amount, address(this), address(this));
        assertEq(withdrawn, shares);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(asset.balanceOf(address(this)), amount);
    }

    function test_MaxDistributionPerSecondPerAsset() public {
        uint256 newMax = 2e18;
        vm.prank(address(core));
        vault.setMaxDistributionPerSecondPerAsset(newMax);
        assertEq(vault.maxDistributionPerSecondPerAsset(), newMax);
    }

    function test_OnlyOwnerCanSetMaxDistribution() public {
        uint256 newMax = 2e18;
        vm.expectRevert();
        vault.setMaxDistributionPerSecondPerAsset(newMax);
        vm.prank(address(core));
        vault.setMaxDistributionPerSecondPerAsset(newMax);
    }

    function test_CannotSetMaxDistributionTooHigh() public {
        uint256 newMax = type(uint256).max;
        vm.prank(address(core));
        vault.setMaxDistributionPerSecondPerAsset(newMax);
        assertEq(vault.maxDistributionPerSecondPerAsset(), type(uint64).max);
    }

    function test_RewardsDistribution(uint256 timeElapsed, uint256 rewardAmount) public {
        assertEq(asset.balanceOf(address(vault)), 0);
        timeElapsed = bound(timeElapsed, 1, REWARDS_CYCLE_LENGTH);
        rewardAmount = bound(rewardAmount, 1e18, 10_000e18);
        deposit(address(this), 1000e18);

        // Advance epochs such that rewards are guaranteed to be distributed in the next epoch
        advanceEpochs(checkIfOnEpochEdge() ? 2 : 1);
        skip(1);
        airdropAsset(address(vault), rewardAmount);
        vault.syncRewardsAndDistribution();

        // Calc expected rewards
        (uint40 cycleEnd, uint40 lastSync, uint256 rewardCycleAmount) = vault.rewardsCycleData();
        uint256 expectedRewards = (uint256(rewardCycleAmount) * timeElapsed) / (cycleEnd - lastSync);
        skip(timeElapsed);
        uint256 actualRewards = vault.calculateRewardsToDistribute(
            LinearRewardsErc4626.RewardsCycleData({
                cycleEnd: cycleEnd,
                lastSync: lastSync,
                rewardCycleAmount: rewardCycleAmount
            }),
            timeElapsed
        );
        uint256 _maxDistribution = (
            vault.maxDistributionPerSecondPerAsset() * timeElapsed * vault.storedTotalAssets()
        ) / vault.PRECISION();
        if (expectedRewards > _maxDistribution) expectedRewards = _maxDistribution; // Cap rewards to max distribution

        assertEq(actualRewards, expectedRewards);
        assertGt(vault.previewDistributeRewards(), 0);
        simulateFeesAndAdvanceEpoch(10e18);
        vault.syncRewardsAndDistribution();
    }

    function test_NoYieldWhenAddedInCurrentEpoch() public {
        deposit(address(this), 1000e18);
        airdropAsset(address(vault), 10e18);
        vault.syncRewardsAndDistribution();
        assertEq(vault.previewDistributeRewards(), 0);
    }

    function test_YieldArrivesInNextEpoch() public {
        deposit(address(this), 1000e18);
        bool onEpochEdge = checkIfOnEpochEdge();
        advanceEpochs(onEpochEdge ? 2 : 1);
        simulateFeesAndAdvanceEpoch(1000e18);
        skip(1);
        vault.syncRewardsAndDistribution();
        skip(1 days);
        assertGt(vault.previewDistributeRewards(), 0);
    }

    function test_LateEpochTransitionAllocatesToNextEpoch() public {
        advanceEpochs(1); // Go to start of new epoch
        deposit(address(this), 1000e18);
        airdropAsset(address(vault), 10e18);
        vault.syncRewardsAndDistribution();
        advanceEpochs(1); // Go to start of new epoch
        uint256 pps = vault.pricePerShare();
        (uint40 cycleEnd,,) = vault.rewardsCycleData();
        uint256 nextEpochTs = vm.getBlockTimestamp() / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH + REWARDS_CYCLE_LENGTH;
        vm.warp(nextEpochTs - 2 hours); // Go to end
        vault.syncRewardsAndDistribution();
        assertEq(vault.pricePerShare(), pps);
        (uint40 cycleEnd2,,) = vault.rewardsCycleData();
        assertNotEq(cycleEnd2, cycleEnd);
        skip(1 hours);
        skip(1 days);
        assertGt(vault.previewDistributeRewards(), 0);
        assertGt(vault.pricePerShare(), pps);
    }

    function test_AirdropDoesntAffectPPS() public {
        uint256 amount = 100e18;
        deposit(address(this), amount);
        airdropAsset(address(this), amount);
        uint256 pps = vault.pricePerShare();
        assertEq(pps, 1e18);
        skip(1 days);
        assertEq(pps, 1e18);
    }

    function test_OFTFunctions() public {
        uint256 amount = 100e18;
        deposit(address(this), amount);
        assertEq(vault.balanceOf(address(this)), amount);
        assertEq(vault.balanceOf(address(vault)), 0);
        assertEq(vault.token(), address(vault));
    }

    function test_DonationBeforeDeploy() public {
        address expected = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        deal(address(asset), address(expected), 1_000e18);
        SavingsReUSD newVault = new SavingsReUSD(address(core), address(registry), Mainnet.LAYERZERO_ENDPOINTV2, address(stablecoin), "Staked reUSD", "sreUSD", type(uint256).max);
        assertEq(expected, address(newVault));
        
        // Deposit
        deal(address(asset), address(this), 1e18);
        asset.approve(address(newVault), 1e18);
        newVault.deposit(1e18, address(this));

        // Sync and advance epoch
        newVault.syncRewardsAndDistribution();
        advanceEpochs(checkIfOnEpochEdge() ? 2 : 1);
        newVault.syncRewardsAndDistribution();
        assertEq(newVault.totalAssets(), 1_001e18);
    }

    function simulateFeesAndAdvanceEpoch(uint256 feeAmount) public {
        airdropAsset(address(feeDeposit), feeAmount);
        advanceEpochs(1);
    }

    function advanceEpochs(uint256 epochs) public {
        uint256 newEpochTs = vm.getBlockTimestamp() / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH + (REWARDS_CYCLE_LENGTH * epochs);
        vm.warp(newEpochTs);
    }

    /**
     * Accounts for the epoch edge in sreUSD which prevents allocating rewards to the current epoch
     * @return timestamp of the first timestamp which yield will begin streaming
     */
    function checkIfOnEpochEdge() public view returns (bool) {
        uint256 newEpochTs = vm.getBlockTimestamp() / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH + (REWARDS_CYCLE_LENGTH);
        if(newEpochTs - vm.getBlockTimestamp() < REWARDS_CYCLE_LENGTH / 40) return true;
        return false;
    }

    // Helper function to deposit and return shares
    function deposit(address user, uint256 amount) public returns (uint256 shares) {
        deal(address(asset), user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    function airdropAsset(address to, uint256 amount) public {
        deal(address(asset), address(user1), amount);
        vm.prank(address(user1));
        asset.transfer(to, amount);
    }

    function _makeInitialGovStakerDeposit() internal {
        deal(address(govToken), address(user1), 1000e18);
        vm.startPrank(address(user1));
        govToken.approve(address(staker), 1000e18);
        staker.stake(1000e18);
        vm.stopPrank();
    }
}