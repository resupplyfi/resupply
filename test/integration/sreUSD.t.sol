// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { StakedReUSD } from "src/protocol/sreusd/sreUSD.sol";
import { ERC20, LinearRewardsErc4626 } from "src/protocol/sreusd/LinearRewardsErc4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/integration/Setup.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { FeeLogger } from "src/protocol/FeeLogger.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";
import { PriceWatcher } from "src/protocol/PriceWatcher.sol";

import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { IRewardHandler } from "src/interfaces/IRewardHandler.sol";

contract sreUSDTest is Setup {
    StakedReUSD public vault;
    FeeLogger public feeLogger;
    PriceWatcher public priceWatcher;


    IERC20 public asset;

    uint32 public constant REWARDS_CYCLE_LENGTH = 7 days;
    uint256 public constant MAX_DISTRIBUTION_PER_SECOND_PER_ASSET = 1e18;

    function setUp() public override {
        super.setUp();
        asset = IERC20(address(stablecoin));

        //deploy sreusd
        vault = new StakedReUSD(
            address(core),
            address(registry),
            lzEndpoint,
            address(asset),
            "Staked reUSD",
            "sreUSD",
            MAX_DISTRIBUTION_PER_SECOND_PER_ASSET
        );

        //deploy fee logger
        feeLogger = new FeeLogger(address(core), address(registry));

        //deploy price watcher
        priceWatcher = new PriceWatcher(address(registry));

        // Setup new fee deposit controller
        vm.startPrank(address(core));
        registry.setAddress("SREUSD", address(vault));
        registry.setAddress("FEE_LOGGER", address(feeLogger));
        registry.setAddress("PRICE_WATCHER", address(priceWatcher));
        FeeDepositController fdcontroller = new FeeDepositController(
            address(core),
            address(registry),
            200_000,
            500,
            500,
            1000
        );
        feeDepositController = IFeeDepositController(address(fdcontroller));
        feeDeposit.setOperator(address(feeDepositController));

        RewardHandler rewardHandlerAddress = new RewardHandler(
            address(core),
            address(registry),
            address(insurancePool),
            address(debtReceiver),
            address(pairEmissionStream),
            address(ipEmissionStream),
            address(ipStableStream)
            );
        rewardHandler = IRewardHandler(address(rewardHandlerAddress));
        registry.setRewardHandler(address(rewardHandler));
        vm.stopPrank();
    }

    function test_Initialization() public {
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.name(), "Staked reUSD");
        assertEq(vault.symbol(), "sreUSD");
        assertEq(vault.maxDistributionPerSecondPerAsset(), MAX_DISTRIBUTION_PER_SECOND_PER_ASSET);
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
        timeElapsed = bound(timeElapsed, 1, REWARDS_CYCLE_LENGTH);
        rewardAmount = bound(rewardAmount, 1e18, 10_000e18);
        deposit(address(this), 1000e18);

        // Advance to the start of new epoch
        uint256 end = block.timestamp / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH + REWARDS_CYCLE_LENGTH;
        vm.warp(end + 1);
        airdropAsset(address(vault), rewardAmount);
        vault.syncRewardsAndDistribution();

        // Calc expected rewards
        (uint40 cycleEnd, uint40 lastSync, uint216 rewardCycleAmount) = vault.rewardsCycleData();
        uint256 expectedRewards = (uint256(rewardCycleAmount) * timeElapsed) / (cycleEnd - lastSync);
        
        skip(timeElapsed);
        assertGt(vault.previewDistributeRewards(), 0);
        uint256 actualRewards = vault.calculateRewardsToDistribute(
            LinearRewardsErc4626.RewardsCycleData({
                cycleEnd: cycleEnd,
                lastSync: lastSync,
                rewardCycleAmount: rewardCycleAmount
            }),
            timeElapsed
        );
        assertEq(actualRewards, expectedRewards);

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
        simulateFeesAndAdvanceEpoch(10e18);
        skip(1); // Needed
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
        uint256 nextEpochTs = block.timestamp / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH + REWARDS_CYCLE_LENGTH;
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

    function test_PreviewSync() public {
        /// TODO
    }

    function test_PreviewDistributeRewards() public {
        /// TODO
    }
    
    function test_RewardsBeforeDeposit() public {
        /// TODO
    }
    
    function test_MigrateFeeDepositAndFeeDepositController() public {
        /// TODO
    }

    function simulateFeesAndAdvanceEpoch(uint256 feeAmount) public {
        airdropAsset(address(feeDeposit), feeAmount);
        advanceEpochs(1);
    }

    function advanceEpochs(uint256 epochs) public {
        uint256 newEpochTs = block.timestamp / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH + (REWARDS_CYCLE_LENGTH * epochs);
        vm.warp(newEpochTs);
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
        deal(address(asset), address(user), amount);
        vm.prank(address(user));
        asset.transfer(to, amount);
    }
}