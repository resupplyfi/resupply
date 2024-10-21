// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {GovStaker} from "../../src/dao/Staking/GovStaker.sol";
import {GovStakerEscrow} from "../../src/dao/staking/GovStakerEscrow.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {IGovStakerEscrow} from "../../src/interfaces/IGovStakerEscrow.sol";
import {IGovStaker} from "../../src/interfaces/IGovStaker.sol";
import {Setup} from "./utils/Setup.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GovStakerTest is Setup {
    MockToken rewardToken1;
    MockToken rewardToken2;
    uint256 epochLength;

    function setUp() public override {
        // Deployments are made in Setup.sol
        super.setUp();
        rewardToken1 = new MockToken("RewardToken1", "RT1");
        rewardToken1.approve(address(staker), type(uint256).max);
        rewardToken2 = new MockToken("RewardToken2", "RT2");
        rewardToken2.approve(address(staker), type(uint256).max);
        stakingToken.mint(user1, 1_000_000 * 10 ** 18);
        vm.prank(user1);
        stakingToken.approve(address(staker), type(uint256).max);
        epochLength = staker.epochLength();
    }

    function test_InitialDeployment() public {
        assertEq(address(staker.stakeToken()), address(stakingToken), "Stake token should be set correctly");
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
        (IGovStaker.AccountData memory acctData, ) = staker.checkpointAccount(_account);
        return acctData.realizedStake;
    }

    function _getPendingStake(address _account) internal returns (uint) {
        (IGovStaker.AccountData memory acctData, ) = staker.checkpointAccount(_account);
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
        
        uint amt = staker.cooldowns(user1).amount;
        
        assertGt(amt, 0, "Amount should be greater than 0");
        assertGt(block.timestamp, staker.cooldowns(user1).end, "Cooldown should be over");
        staker.unstake(user1, user1);
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
        staker.stakeFor(dev, 100 * 10 ** 18);
        staker.cooldownFor(dev, 100 * 10 ** 18);
        staker.unstakeFor(dev, dev);
        // This should fail since user1 is not approved to stake for dev
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

        vm.expectRevert("Invalid duration");
        staker.setCooldownEpochs(500);

        staker.setCooldownEpochs(2);
        assertEq(staker.cooldownEpochs(), 2, "Cooldown duration should be 5");
        assertEq(staker.isCooldownEnabled(), true, "Cooldown should be enabled");
        vm.stopPrank();
    }

    function warmupWait() internal view returns (uint) {
        return epochLength;
    }

    function getEpoch() public view returns (uint) {
        return staker.getEpoch();
    }

    function getUserCooldownEnd(address _account) public view returns (uint) {
        IGovStaker.UserCooldown memory cooldown = staker.cooldowns(_account);
        return uint(cooldown.end);
    }

    function getUserCooldownAmount(address _account) public view returns (uint) {
        IGovStaker.UserCooldown memory cooldown = staker.cooldowns(_account);
        return uint(cooldown.amount);
    }
}
