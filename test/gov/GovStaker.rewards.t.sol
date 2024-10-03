// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {GovStaker} from "../../src/dao/staking/GovStaker.sol";
import {GovStakerEscrow} from "../../src/dao/staking/GovStakerEscrow.sol";
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

    

    function test_AddReward() public {
        uint amountToStake = 100 * 10 ** 18;
        
        // Add rewards
        addRewardToken(address(rewardToken1), 1 days);
        addRewardToken(address(rewardToken2), 1 days);
        vm.warp(block.timestamp + 1 days);

        // Stake
        vm.prank(user1);
        staker.stake(amountToStake);

        vm.warp(block.timestamp + 1 days);
        // We haven't notified yet. Verify all rewards are 0.
        uint earnedToken1 = staker.earned(user1, address(rewardToken1));
        assertEq(earnedToken1, 0, "earnedToken1 should be 0");
        uint earnedToken2 = staker.earned(user1, address(rewardToken2));
        assertEq(earnedToken2, 0, "earnedToken2 should be 0");
        uint[] memory earnedMulti = staker.earnedMulti(user1);
        assertEq(earnedMulti[0], 0, "earnedMulti[0] should be 0");
        assertEq(earnedMulti[1], 0, "earnedMulti[1] should be 0");

        // Now let's distribute some rewards.
        staker.notifyRewardAmount(address(rewardToken1), 1_000 * 10 ** 18);
        staker.notifyRewardAmount(address(rewardToken2), 2_000 * 10 ** 18);
        vm.warp(block.timestamp + 1 days);

        earnedToken1 = staker.earned(user1, address(rewardToken1));
        earnedToken2 = staker.earned(user1, address(rewardToken2));
        assertGt(earnedToken1, 0, "earnedToken1 should be 0");
        assertGt(earnedToken2, 0, "earnedToken2 should be 0");
        earnedMulti = staker.earnedMulti(user1);
        assertGt(earnedMulti[0], 0, "earnedMulti[0] should be 0");
        assertGt(earnedMulti[1], 0, "earnedMulti[1] should be 0");
        assertEq(earnedMulti[0], earnedToken1, "earnedMulti[0] should be equal to earnedToken1");
        assertEq(earnedMulti[1], earnedToken2, "earnedMulti[1] should be equal to earnedToken2");

        console.log("earned", earnedToken1/1e18, earnedToken2/1e18);
    }

    function test_CannotAddDuplicateReward() public {
        addRewardToken(address(rewardToken1), 1 days);
        vm.expectRevert("Reward already added");
        addRewardToken(address(rewardToken1), 1 days);
    }

    /* ========== HELPER FUNCTIONS ========== */
    function addRewardToken(address _token, uint _duration) internal {
        staker.addReward(
            _token, // rewardsToken
            address(this),         // distributor
            _duration          // duration
        );
    }

    function notifyRewardAmount(address _token, uint _amount) internal {
        staker.notifyRewardAmount(_token, _amount);
    }
}
