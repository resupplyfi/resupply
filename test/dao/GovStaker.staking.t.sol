// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {GovStaker} from "../../src/dao/staking/GovStaker.sol";
import {GovStakerEscrow} from "../../src/dao/staking/GovStakerEscrow.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {IGovStakerEscrow} from "../../src/interfaces/IGovStakerEscrow.sol";
import {IGovStaker} from "../../src/interfaces/IGovStaker.sol";
import {Setup} from "../Setup.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GovStakerStakingTest is Setup {
    MockToken rewardToken1;
    MockToken rewardToken2;

    function setUp() public override {
        // Deployments are made in Setup.sol
        super.setUp();
        rewardToken1 = new MockToken("RewardToken1", "RT1");
        rewardToken1.approve(address(staker), type(uint256).max);
        rewardToken2 = new MockToken("RewardToken2", "RT2");
        rewardToken2.approve(address(staker), type(uint256).max);
        deal(address(stakingToken), user1, 1_000_000 * 10 ** 18);
        deal(address(stakingToken), address(this), 1_000_000 * 10 ** 18);
        stakingToken.approve(address(staker), type(uint256).max);
        vm.prank(user1);
        stakingToken.approve(address(staker), type(uint256).max);
    }

    function test_InitialDeployment() public {
        assertEq(address(staker.stakeToken()), address(stakingToken), "Stake token should be set correctly");
    }

    function test_UnstakeWithZeroCooldownEpochs() public {
        uint amountToStake = 10_000e18;
        stakeSomeAndWait(address(this), amountToStake);
        vm.prank(address(core));
        staker.setCooldownEpochs(0);

        uint unstakableAmount = staker.getUnstakableAmount(address(this));
        uint unstakedAmount = staker.unstake(address(this), address(this));
        assertEq(unstakedAmount, unstakableAmount, "Unstaked amount should be equal to unstakable amount");
    }

    function test_Stake() public {
        uint amountToStake = 100 * 10 ** 18;
        vm.prank(user1);
        staker.stake(user1, amountToStake);

        assertEq(staker.balanceOf(user1), amountToStake, "Stake balance should be updated");
        assertEq(stakingToken.balanceOf(address(staker)), amountToStake, "Token should be transferred to staker");
        assertEq(staker.getAccountWeight(user1), 0, "Weight should be 0");
        vm.warp(block.timestamp + epochLength); // Test weight increase
        assertEq(staker.getAccountWeight(user1), amountToStake, "Weight should be 0");

        vm.warp(block.timestamp + warmupWait() * 100);
        staker.checkpointAccount(user1);

        staker.stake(100e18);
    }

    function test_AddReward() public {
        uint amountToStake = 100 * 10 ** 18;
        
        // Add rewards
        vm.startPrank(staker.owner());
        staker.addReward(
            address(rewardToken1), // rewardsToken
            address(this),         // distributor
            60 * 60 * 24           // duration
        );
        staker.addReward(
            address(rewardToken2), // rewardsToken
            address(this),         // distributor
            60 * 60 * 24        // duration
        );
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);

        uint earned1 = staker.earned(user1, address(rewardToken1));
        uint earned2 = staker.earned(user1, address(rewardToken2));

        vm.prank(user1);
        staker.stake(user1, amountToStake);

        staker.notifyRewardAmount(address(rewardToken1), 1_000 * 10 ** 18);
        staker.notifyRewardAmount(address(rewardToken2), 2_000 * 10 ** 18);

        vm.warp(block.timestamp + 1 days);

        earned1 = staker.earned(user1, address(rewardToken1));
        earned2 = staker.earned(user1, address(rewardToken2));
    }

    function _getRealizedStake(address _account) internal returns (uint) {
        (GovStaker.AccountData memory acctData, ) = staker.checkpointAccount(_account);
        return acctData.realizedStake;
    }

    function _getPendingStake(address _account) internal returns (uint) {
        (GovStaker.AccountData memory acctData, ) = staker.checkpointAccount(_account);
        return acctData.pendingStake;
    }

    function test_StakeAndUnstake() public {
        uint amountToStake = stakingToken.balanceOf(user1);
        stakeSomeAndWait(user1, amountToStake);
        
        assertEq(staker.balanceOf(user1), amountToStake, "Stake should be updated correctly");
        assertEq(stakingToken.balanceOf(address(staker)), amountToStake, "Tokens should be transferred to staker");
        vm.warp(block.timestamp + warmupWait()); // Warm up wait
        uint realizedStake = _getRealizedStake(user1);
        assertEq(realizedStake, amountToStake, "Realized stake should be equal to staked amount");

        // Initiate cooldown and unstake
        vm.startPrank(user1);
        staker.cooldown(user1, amountToStake);
        uint cooldownEpochs = staker.cooldownEpochs();
        skip(cooldownEpochs * epochLength + 1);
        
        (uint104 _end ,uint152 amt) = staker.cooldowns(user1);
        
        assertGt(amt, 0, "Amount should be greater than 0");
        assertGt(block.timestamp, _end, "Cooldown should be over");
        uint unstakableAmount = staker.getUnstakableAmount(user1);
        uint unstakedAmount = staker.unstake(user1, user1);
        assertEq(unstakedAmount, unstakableAmount, "Unstaked amount should be equal to unstakable amount");
        vm.stopPrank();

        assertEq(staker.balanceOf(user1), 0, "Balance after unstake should be zero");
        assertEq(stakingToken.balanceOf(user1), amountToStake, "Token should be returned to user");
    }

    function test_MultipleStake() public {
        uint amountToStake = (stakingToken.balanceOf(user1) - 1) / 2;
        stakeSome(amountToStake);
        checkExpectedBalanceAndWeight(
            amountToStake,  // balanceOf
            0,              // expectedWeight
            amountToStake,  // expectedTotalSupply
            0               // expectedTotalWeight
        );

        // Advance to next epoch, allowing weight to have grown.
        vm.warp(block.timestamp + warmupWait());
        checkExpectedBalanceAndWeight(
            amountToStake,  // balanceOf
            amountToStake,      // expectedWeight
            amountToStake ,  // expectedTotalSupply
            amountToStake       // expectedTotalWeight
        );

        stakeSome(amountToStake);
        checkExpectedBalanceAndWeight(
            amountToStake * 2,  // balanceOf
            amountToStake,      // expectedWeight
            amountToStake * 2,  // expectedTotalSupply
            amountToStake       // expectedTotalWeight
        );

        vm.warp(block.timestamp + warmupWait());
        checkExpectedBalanceAndWeight(
            amountToStake * 2,  // balanceOf
            amountToStake * 2,  // expectedWeight
            amountToStake * 2,  // expectedTotalSupply
            amountToStake * 2   // expectedTotalWeight
        );
    }

    function test_MultipleUserStake() public {
        // TODO
    }

    function test_StakeForCooldownForAndUnstakeFor() public {
        // TODO
    }

    function testFail_StakeForCooldownForAndUnstakeFor() public {
        vm.prank(user1);
        staker.stake(dev, 100 * 10 ** 18);
        staker.cooldown(dev, 100 * 10 ** 18);
        staker.unstake(dev, dev); // This should fail since user1 is not approved to stake for dev
    }

    function test_CoolDown() public {
        // TODO
    }

    function checkExpectedBalanceAndWeight(
        uint expectedBalance, 
        uint expectedWeight, 
        uint expectedTotalSupply, 
        uint expectedTotalWeight
    ) internal {
        assertEq(staker.balanceOf(user1), expectedBalance, "Stake balance doesnt match");
        assertEq(staker.totalSupply(), expectedTotalSupply, "Total supply doesnt match");
        assertEq(staker.getAccountWeight(user1), expectedWeight, "Weight doesnt match");
        assertEq(staker.getAccountWeightAt(user1, getEpoch()), expectedWeight, "getAccountWeightAt doesnt match");
        assertEq(staker.getTotalWeight(), expectedTotalWeight, "getTotalWeight doesnt match");
        assertEq(staker.getTotalWeightAt(getEpoch()), expectedTotalWeight, "getTotalWeightAt doesnt match");
    }


    function stakeSomeAndWait(address user, uint amountToStake) internal {
        vm.prank(user);
        stakingToken.approve(address(staker), amountToStake);
        deal(address(stakingToken), user, amountToStake);
        vm.prank(user);
        staker.stake(user, amountToStake);
        skip(warmupWait());
    }

    function stakeSome(uint amountToStake) internal {
        vm.prank(user1);
        staker.stake(user1,amountToStake);
    }

    function test_Unstake() public {
        uint amountToStake = stakingToken.balanceOf(user1);
        assertGt(amountToStake, 0, "Amount to stake should be greater than 0");
        stakeSomeAndWait(user1, amountToStake);

        // Cooldown
        vm.startPrank(user1);
        staker.cooldown(user1, amountToStake);
        uint cooldownEpochs = staker.cooldownEpochs();
        vm.warp(block.timestamp + (cooldownEpochs + 1) * epochLength);
        uint amount = staker.unstake(user1, user1);
        assertEq(amount, amountToStake, "Unstake amount should be equal to staked amount");
        vm.stopPrank();
    }

    function test_UnstakePartial() public {
        uint amountToStake = stakingToken.balanceOf(user1);
        assertGt(amountToStake, 0, "Amount to stake should be greater than 0");
        stakeSomeAndWait(user1, amountToStake);
        skip(warmupWait() * 2);
        // Cooldown
        vm.startPrank(user1);
        staker.cooldown(user1, amountToStake / 2);
        vm.warp(getUserCooldownEnd(user1));
        uint amount = staker.unstake(user1, user1);
        assertEq(amount, amountToStake / 2, "Unstake amount should be equal to staked amount");
        vm.stopPrank();
    }

    function test_SetCooldownEpochs() public {
        uint amountToStake = stakingToken.balanceOf(user1);
        stakeSomeAndWait(user1, amountToStake);
        vm.startPrank(staker.owner());

        staker.setCooldownEpochs(0);
        assertEq(staker.cooldownEpochs(), 0, "Cooldown duration should be 0");
        assertEq(staker.isCooldownEnabled(), false, "Cooldown should be disabled");

        vm.expectRevert(GovStaker.InvalidDuration.selector);
        staker.setCooldownEpochs(500);

        staker.setCooldownEpochs(2);
        assertEq(staker.cooldownEpochs(), 2, "Cooldown duration should be 5");
        assertEq(staker.isCooldownEnabled(), true, "Cooldown should be enabled");
        vm.stopPrank();
    }


    // must be able to migrate to a new staker
    // cannot initiate a cooldown
    // Vest claims must be staked

    function test_ConfirmPermaStaker() public {
        staker.stake(address(this), 100 * 10 ** 18);
        assertEq(staker.balanceOf(address(this)), 100 * 10 ** 18, "Balance should be 100");
        // make perma staker
        assertEq(staker.isPermaStaker(address(this)), false, "Account should not be a perma staker");
        staker.irreversiblyCommitAccountAsPermanentStaker(address(this));
        assertEq(staker.isPermaStaker(address(this)), true, "Account should be a perma staker");

        vm.expectRevert("perma staker account");
        staker.cooldown(address(this), 100 * 10 ** 18);

        uint unstakableAmount = staker.getUnstakableAmount(address(this));
        uint unstakedAmount = staker.unstake(address(this), address(this));
        assertEq(unstakedAmount, unstakableAmount, "Unstaked amount should be equal to unstakable amount");
    }

    function test_ShouldBeAbleToRecoverTokensWhenPermaStakingDuringPreexistingCooldown() public {
        uint amount = 100 * 10 ** 18;
        staker.stake(address(this), amount);
        skip(warmupWait());
        staker.cooldown(address(this), amount); // cooldown before
        staker.irreversiblyCommitAccountAsPermanentStaker(address(this));
        skip(cooldownWait());
        uint unstakableAmount = staker.getUnstakableAmount(address(this));
        assertEq(unstakableAmount, amount, "Unstakable amount should be equal to staked amount");
        uint unstakedAmount = staker.unstake(address(this), address(this));
        assertEq(unstakedAmount, amount, "Unstaked amount should be equal to unstakable amount");
        assertEq(staker.balanceOf(address(this)), 0, "Balance should be 0");
    }

    function warmupWait() internal view returns (uint) {
        return epochLength;
    }

    function cooldownWait() internal view returns (uint) {
        return epochLength * staker.cooldownEpochs();
    }

    function getEpoch() public view returns (uint) {
        return staker.getEpoch();
    }

    function getUserCooldownEnd(address _account) public view returns (uint) {
        (uint104 _end ,) = staker.cooldowns(_account);
        return uint(_end);
    }

    function getUserCooldownAmount(address _account) public view returns (uint) {
        (,uint152 amt) = staker.cooldowns(_account);
        return uint(amt);
    }
}
