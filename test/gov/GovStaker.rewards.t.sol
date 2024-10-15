pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {GovStaker} from "../../src/dao/staking/GovStaker.sol";
import {GovStakerEscrow} from "../../src/dao/staking/GovStakerEscrow.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {IGovStakerEscrow} from "../../src/interfaces/IGovStakerEscrow.sol";
import {Setup} from "./utils/Setup.sol";

contract OperationTest is Setup {
    MockToken public rewardToken;
    MockToken public rewardToken2;
    uint256 public constant EPOCH_LENGTH = 2 days;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.

    address public keeper = address(4);
    address public management = address(this);

    // Integer variables that will be used repeatedly.
    uint256 public MAX_BPS = 10_000;
    uint256 public WEEK = 1 weeks;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;

    event RewardPaid(address indexed user, address indexed rewardToken, uint256 reward);

    function setUp() public override {
        super.setUp();

        rewardToken = new MockToken("RewardToken1", "RT1");
        rewardToken2 = new MockToken("RewardToken2", "RT2");

        stakingToken.approve(address(staker), type(uint256).max);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        for (uint256 i = 0; i < users.length; i++) {    
            vm.prank(users[i]);
            stakingToken.approve(address(staker), type(uint256).max);
            stakingToken.mint(users[i], 1_000_000 * 10 ** 18);
        }
    }

    function test_basicOperation() public {
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        uint256 amountToStake = stakingToken.mint(user1, amount);
        assertGt(stakingToken.balanceOf(user1), 0);

        // stake our assets
        vm.startPrank(user1);
        vm.expectRevert("invalid amount");
        staker.stake(0);
        stakingToken.approve(address(staker), type(uint256).max);
        staker.stake(amountToStake);
        vm.stopPrank();
        assertEq(staker.balanceOf(user1), amountToStake);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        vm.startPrank(management);

        // will revert if we haven't added it first
        vm.expectRevert("!authorized");
        staker.notifyRewardAmount(address(rewardToken), 1e18);

        // add token to rewards array
        staker.addReward(address(rewardToken), management, 3*WEEK);
        rewardToken.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken), 1e18);
        vm.stopPrank();

        // only owner can setup rewards
        vm.expectRevert("!authorized");
        vm.prank(user1);
        staker.addReward(address(rewardToken), management, WEEK);

        // check how much rewards we have for the week
        uint256 firstWeekRewards = staker.getRewardForDuration(
            address(rewardToken)
        );
        assertGt(firstWeekRewards, 0);
        console2.log("Total Rewards per week (starting):%e", firstWeekRewards);

        // sleep to earn some profits
        skip(1 weeks);

        // check earnings, get reward
        uint256 earned = staker.earned(user1, address(rewardToken));
        assertGt(earned, 0);
        console2.log("User Rewards earned after 24 hours:%e", earned);
        vm.prank(user1);
        staker.getReward();
        assertGe(rewardToken.balanceOf(user1), earned);
        uint256 currentProfits = rewardToken.balanceOf(user1);

        // can't withdraw zero
        vm.startPrank(user1);
        vm.expectRevert("invalid amount");
        staker.cooldown(0);

        // user withdraws ~half of their assets
        staker.cooldown(amount / 2);

        // sleep to earn some profits
        skip(86400);

        // user fully exits
        assertGt(staker.balanceOf(user1), 0, "ABC");


        staker.exit();
        uint256 totalGains = rewardToken.balanceOf(user1);
        assertGt(totalGains, currentProfits);
        console2.log("User Rewards earned after 48 hours:%e", totalGains);
        assertEq(staker.balanceOf(user1), 0);
    }

    function test_multipleRewards() public {
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        uint256 amountToStake = stakingToken.mint(user1, amount);
        assertGt(stakingToken.balanceOf(user1), 0);

        // stake our assets
        vm.startPrank(user1);
        vm.expectRevert("invalid amount");
        staker.stake(0);
        stakingToken.approve(address(staker), type(uint256).max);
        staker.stake(amountToStake);
        vm.stopPrank();
        assertEq(staker.balanceOf(user1), amountToStake);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        airdrop(rewardToken2, management, 1_000e18);
        vm.startPrank(management);

        // add token to rewards array
        staker.addReward(address(rewardToken), management, 2 * 1 weeks);
        rewardToken.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken), 1e18);

        // can't add the same token
        vm.expectRevert("Reward already added");
        staker.addReward(address(rewardToken), management, 3 * 1 weeks);

        // can't adjust duration while we're in progress
        vm.expectRevert("Rewards active");
        staker.setRewardsDuration(address(rewardToken), 3* 1 weeks);

        // can't add zero address
        vm.expectRevert("No zero address");
        staker.addReward(address(rewardToken), address(0), 3 * 1 weeks);
        vm.expectRevert("No zero address");
        staker.addReward(address(0), management, WEEK);

        // add second token
        // duration must be >0
        vm.expectRevert("Must be >0");
        staker.addReward(address(rewardToken2), management, 0);
        staker.addReward(address(rewardToken2), management, 3 * 1 weeks);
        rewardToken2.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken2), 100e18);
        vm.stopPrank();

        // check reward token length
        uint256 length = staker.rewardTokensLength();
        assertEq(length, 2);

        // check how much rewards we have for the week
        uint256 firstWeekRewards = staker.getRewardForDuration(
            address(rewardToken)
        );
        uint256 firstWeekRewards2 = staker.getRewardForDuration(
            address(rewardToken2)
        );
        assertGt(firstWeekRewards, 0);
        assertGt(firstWeekRewards2, 0);

        // sleep to earn some profits
        skip(1 weeks);

        // check earnings
        uint256 earned = staker.earned(user1, address(rewardToken));
        assertGt(earned, 0);
        uint256 earnedTwo = staker.earned(user1, address(rewardToken2));
        assertGt(earnedTwo, 0);

        uint256[] memory earnedAmounts = new uint256[](2);
        earnedAmounts = staker.earnedMulti(user1);
        assertEq(earned, earnedAmounts[0]);
        assertEq(earnedTwo, earnedAmounts[1]);

        // user gets reward, withdraws
        vm.startPrank(user1);
        staker.getReward();
        assertGe(rewardToken.balanceOf(user1), earned);
        assertGe(rewardToken2.balanceOf(user1), earnedTwo);
        uint256 currentProfitsTwo = rewardToken2.balanceOf(user1);

        // user withdraws ~half of their assets
        // staker.cooldown(amount / 2);

        // sleep to earn some profits
        skip(1 weeks);

        // user fully exits
        console.log("User balance before exit: %e", staker.balanceOf(user1));
        earned = staker.earned(user1, address(rewardToken2));
        console.log("User earned before exit: %e", earned);
        assertGt(staker.balanceOf(user1), 0);
        vm.expectEmit(true, true, false, true);
        emit RewardPaid(user1, address(rewardToken2), earned);

        staker.exit();
        assertEq(staker.balanceOf(user1), 0);
        uint256 totalGainsTwo = rewardToken2.balanceOf(user1);
        console.log("User balance after exit: %e", totalGainsTwo);
        assertGt(totalGainsTwo, currentProfitsTwo);
        assertEq(staker.balanceOf(user1), 0);
        vm.stopPrank();
    }

    function test_extendRewards() public {
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        uint256 amountToStake = stakingToken.mint(user1, amount);
        assertGt(stakingToken.balanceOf(user1), 0);

        // stake our assets
        vm.startPrank(user1);
        stakingToken.approve(address(staker), type(uint256).max);
        staker.stake(amountToStake);
        vm.stopPrank();
        assertEq(staker.balanceOf(user1), amountToStake);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        airdrop(rewardToken2, management, 1_000e18);
        vm.startPrank(management);

        // add token to rewards array
        staker.addReward(address(rewardToken), management, WEEK);
        rewardToken.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken), 1e18);

        // add second token
        staker.addReward(address(rewardToken2), management, WEEK);
        rewardToken2.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken2), 100e18);
        vm.stopPrank();

        // check reward token length
        uint256 length = staker.rewardTokensLength();
        assertEq(length, 2);

        // check how much rewards we have for the week
        uint256 firstWeekRewards = staker.getRewardForDuration(
            address(rewardToken)
        );
        uint256 firstWeekRewards2 = staker.getRewardForDuration(
            address(rewardToken2)
        );
        assertGt(firstWeekRewards, 0);
        assertGt(firstWeekRewards2, 0);

        // sleep to earn some profits
        skip(86400);

        // check earnings
        uint256 earned = staker.earned(user1, address(rewardToken));
        assertGt(earned, 0);
        uint256 earnedTwo = staker.earned(user1, address(rewardToken2));
        assertGt(earnedTwo, 0);

        uint256[] memory earnedAmounts = new uint256[](2);
        earnedAmounts = staker.earnedMulti(user1);
        assertEq(earned, earnedAmounts[0]);
        assertEq(earnedTwo, earnedAmounts[1]);

        // user gets reward, withdraws
        vm.prank(user1);
        staker.getReward();
        assertGe(rewardToken.balanceOf(user1), earned);
        assertGe(rewardToken2.balanceOf(user1), earnedTwo);

        // add some more rewards
        vm.prank(management);
        staker.notifyRewardAmount(address(rewardToken), 1e18);
        uint256 firstWeekRewardsCheckTwo = staker.getRewardForDuration(
            address(rewardToken)
        );
        uint256 firstWeekRewards2CheckTwo = staker.getRewardForDuration(
            address(rewardToken2)
        );
        assertEq(firstWeekRewards2, firstWeekRewards2CheckTwo);
        assertGt(firstWeekRewardsCheckTwo, firstWeekRewards);

        // TODO: ADD MORE TESTING HERE
    }


    function test_multiUserMultiRewards() public {
        // Here we should have multiple users, each with different amount
        // we rewards over time at an irregular interval, and also simulate
        // irregular staking and unstaking to make sure that at the end, all
        // rewards are distributed.
        uint amountToStake = 100 * 10 ** 18;

        addRewards(address(rewardToken));
        addRewards(address(rewardToken2));

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256 i;
        for (; i < 20; i++) {
            for (uint256 x = 0; x < users.length; x++) {
                uint bal = staker.balanceOf(users[x]);
                if (i % 2 == 0 || x > 0) {
                    vm.prank(users[x]);
                    staker.stake(amountToStake / (x + 1));
                }
                if (bal > 0) {
                    vm.prank(users[x]);
                    staker.cooldown(bal / (x + 2));
                }
                if (i % 2 == 0) airdropAndNotify(rewardToken2, users[x], 500e18);
                airdropAndNotify(rewardToken, users[x], 250e18);
            }
            skip(1 weeks);
        }
        
        for (i = 0; i < users.length; i++) {
            console2.log("User getting reward", i, staker.earned(users[i], address(rewardToken)) / 1e18);
            vm.prank(users[i]);
            staker.getReward();
        }

        // check that the rewards are gone
        assertLt(rewardToken.balanceOf(address(staker)), 1e18);
        assertLt(rewardToken2.balanceOf(address(staker)), 1e18);
    }

    function addRewards(address _token) public {
        vm.prank(management);
        staker.addReward(_token, management, 1 weeks);
        rewardToken.approve(address(staker), type(uint256).max);
    }

    // Helpers
    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function airdropAndNotify(ERC20 _asset, address _to, uint256 _amount) public {
        airdrop(_asset, _to, _amount);
        vm.prank(management);
        staker.notifyRewardAmount(address(rewardToken), 1e18);
    }
}