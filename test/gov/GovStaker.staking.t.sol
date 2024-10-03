// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/dao/GovStaker.sol";
import "../../src/dao/GovStakerEscrow.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {IGovStakerEscrow} from "../../src/interfaces/IGovStakerEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GovStakerTest is Test {
    GovStaker staker;
    GovStakerEscrow escrow;
    MockToken token;
    MockToken rewardToken1;
    MockToken rewardToken2;
    address deployer;
    address user1;
    uint256 public constant EPOCH_LENGTH = 60 * 60 * 24 * 2;

    function setUp() public {
        deployer = address(this);
        user1 = address(0x1);

        token = new MockToken("GovToken", "GOV");
        rewardToken1 = new MockToken("RewardToken1", "RT1");
        rewardToken2 = new MockToken("RewardToken2", "RT2");

        uint256 nonce = vm.getNonce(deployer);
        address escrowAddress = computeCreateAddress(deployer, nonce);
        address govStakingAddress = computeCreateAddress(deployer, nonce + 1);
        escrow = new GovStakerEscrow(govStakingAddress, address(token));
        staker = new GovStaker(
            address(token),    // stakeToken
            deployer,          // owner
            EPOCH_LENGTH,      // EPOCH_LENGTH
            IGovStakerEscrow(escrowAddress), // Escrow
            10                  // cooldownEpochs
        );

        token.approve(address(staker), type(uint256).max);
        token.transfer(user1, 10000 * 10 ** 18);
        vm.prank(user1);
        token.approve(address(staker), type(uint256).max);

        rewardToken1.approve(address(staker), type(uint256).max);
        rewardToken2.approve(address(staker), type(uint256).max);
    }

    function test_InitialDeployment() public {
        assertEq(staker.owner(), deployer, "Owner should be deployer");
        assertEq(address(staker.stakeToken()), address(token), "Stake token should be set correctly");
    }

    function test_Stake() public {
        uint amountToStake = 100 * 10 ** 18;
        vm.prank(user1);
        staker.stake(amountToStake);

        assertEq(staker.balanceOf(user1), amountToStake, "Stake balance should be updated");
        assertEq(token.balanceOf(address(staker)), amountToStake, "Token should be transferred to staker");
        assertEq(staker.getAccountWeight(user1), 0, "Weight should be 0");
        vm.warp(block.timestamp + EPOCH_LENGTH); // Test weight increase
        assertEq(staker.getAccountWeight(user1), amountToStake, "Weight should be 0");

        vm.warp(block.timestamp + warmupWait() * 100);
        staker.checkpointAccount(user1);
    }

    function test_AddReward() public {
        uint amountToStake = 100 * 10 ** 18;
        
        // Add rewards
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

        vm.warp(block.timestamp + 1 days);

        uint earned1 = staker.earned(user1, address(rewardToken1));
        uint earned2 = staker.earned(user1, address(rewardToken2));
        console.log("earned", earned1, earned2);

        vm.prank(user1);
        staker.stake(amountToStake);

        staker.notifyRewardAmount(address(rewardToken1), 1_000 * 10 ** 18);
        staker.notifyRewardAmount(address(rewardToken2), 2_000 * 10 ** 18);

        vm.warp(block.timestamp + 1 days);

        earned1 = staker.earned(user1, address(rewardToken1));
        earned2 = staker.earned(user1, address(rewardToken2));

        console.log("earned", earned1/1e18, earned2/1e18);
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
        uint amountToStake = token.balanceOf(user1);
        stakeSomeAndWait(amountToStake);
        
        assertEq(staker.balanceOf(user1), amountToStake, "Stake should be updated correctly");
        assertEq(token.balanceOf(address(staker)), amountToStake, "Tokens should be transferred to staker");
        vm.warp(block.timestamp + warmupWait()); // Warm up wait
        uint realizedStake = _getRealizedStake(user1);
        assertEq(realizedStake, amountToStake, "Realized stake should be equal to staked amount");

        // Initiate cooldown and unstake
        vm.startPrank(user1);
        staker.cooldown(amountToStake);
        uint cooldownEpochs = staker.cooldownEpochs();
        vm.warp(block.timestamp + (cooldownEpochs + 1) * EPOCH_LENGTH);
        
        staker.unstake(user1);
        // staker.unstake(amountToStake, user1);
        vm.stopPrank();

        assertEq(staker.balanceOf(user1), 0, "Balance after unstake should be zero");
        assertEq(token.balanceOf(user1), amountToStake, "Token should be returned to user");
    }

    function test_MultipleStake() public {
        uint amountToStake = (token.balanceOf(user1) - 1) / 2;
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
        staker.stakeFor(deployer, 100 * 10 ** 18);
        staker.cooldownFor(deployer, 100 * 10 ** 18);
        staker.unstakeFor(deployer, deployer);
        // This should fail since user1 is not approved to stake for deployer
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


    function stakeSomeAndWait(uint amountToStake) internal {
        vm.prank(user1);
        staker.stake(amountToStake);
        vm.warp(block.timestamp + warmupWait());
    }

    function stakeSome(uint amountToStake) internal {
        vm.prank(user1);
        staker.stake(amountToStake);
    }

    function test_Unstake() public {
        uint amountToStake = token.balanceOf(user1);
        assertGt(amountToStake, 0, "Amount to stake should be greater than 0");
        stakeSomeAndWait(amountToStake);
        console.log("weight", staker.getAccountWeight(user1), staker.balanceOf(user1));

        // Cooldown
        vm.startPrank(user1);
        staker.cooldown(amountToStake);
        uint cooldownEpochs = staker.cooldownEpochs();
        vm.warp(block.timestamp + (cooldownEpochs + 1) * EPOCH_LENGTH);
        uint amount = staker.unstake(user1);
        assertEq(amount, amountToStake, "Unstake amount should be equal to staked amount");
        vm.stopPrank();
    }

    function test_UnstakePartial() public {
        uint amountToStake = token.balanceOf(user1);
        assertGt(amountToStake, 0, "Amount to stake should be greater than 0");
        stakeSomeAndWait(amountToStake);
        console.log("weight", staker.getAccountWeight(user1), staker.balanceOf(user1));

        // Cooldown
        vm.startPrank(user1);
        staker.cooldown(amountToStake / 2);
        uint cooldownEpochs = staker.cooldownEpochs();
        vm.warp(block.timestamp + (cooldownEpochs + 1) * EPOCH_LENGTH);
        console.log("cooldown data", getUserCooldownEnd(user1), getUserCooldownAmount(user1));
        uint amount = staker.unstake(user1);
        assertEq(amount, amountToStake / 2, "Unstake amount should be equal to staked amount");
        vm.stopPrank();
    }

    function test_SetCooldownEpochs() public {
        uint amountToStake = token.balanceOf(user1);
        stakeSomeAndWait(amountToStake);
        vm.startPrank(staker.owner());

        staker.setCooldownEpochs(0);
        assertEq(staker.cooldownEpochs(), 0, "Cooldown duration should be 0");
        assertEq(staker.isCooldownEnabled(), false, "Cooldown should be disabled");

        staker.setCooldownEpochs(5);
        assertEq(staker.cooldownEpochs(), 5, "Cooldown duration should be 5");
        assertEq(staker.isCooldownEnabled(), true, "Cooldown should be enabled");
        vm.stopPrank();
    }

    function warmupWait() internal pure returns (uint) {
        return EPOCH_LENGTH;
    }

    function getEpoch() public view returns (uint) {
        return staker.getEpoch();
    }

    function getUserCooldownEnd(address _account) public view returns (uint) {
        (uint104 end,) = staker.cooldowns(_account);
        return end;
    }
    function getUserCooldownAmount(address _account) public view returns (uint) {
        (, uint152 amount) = staker.cooldowns(_account);
        return uint(amount);
    }
}
