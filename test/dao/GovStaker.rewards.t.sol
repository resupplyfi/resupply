pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { GovStaker } from "../../src/dao/staking/GovStaker.sol";
import { GovStakerEscrow } from "../../src/dao/staking/GovStakerEscrow.sol";
import { MockToken } from "../mocks/MockToken.sol";
import { IGovStakerEscrow } from "../../src/interfaces/IGovStakerEscrow.sol";
import { IGovStaker } from "../../src/interfaces/IGovStaker.sol";
import { Setup } from "../Setup.sol";
import { MultiRewardsDistributor } from "../../src/dao/staking/MultiRewardsDistributor.sol";

contract GovStakerRewardsTest is Setup {
    MockToken public rewardToken;
    MockToken public rewardToken2;
    MockToken public sweepToken;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public keeper = address(4);
    address public owner;

    // Integer variables that will be used repeatedly.
    uint256 public MAX_BPS = 10_000;
    uint256 public WEEK = 1 weeks;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;

    event RewardPaid(address indexed user, address indexed rewardToken, address indexed claimTo, uint256 reward);
             
    function setUp() public override {
        super.setUp();
        staker = new GovStaker(address(core), address(registry), address(govToken), 2);
        owner = address(core);
        rewardToken = new MockToken("RewardToken1", "RT1");
        rewardToken2 = new MockToken("RewardToken2", "RT2");
        sweepToken = new MockToken("SweepToken", "ST");
        rewardToken.mint(owner, 1_000_000 * 10 ** 18);
        rewardToken2.mint(owner, 1_000_000 * 10 ** 18);
        vm.startPrank(owner);
        rewardToken.approve(address(staker), type(uint256).max);
        rewardToken2.approve(address(staker), type(uint256).max);
        vm.stopPrank();

        stakingToken.approve(address(staker), type(uint256).max);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        for (uint256 i = 0; i < users.length; i++) {    
            vm.prank(users[i]);
            stakingToken.approve(address(staker), type(uint256).max);
            mintGovToken(users[i], 1_000_000 * 10 ** 18);
        }
    }

    function test_RewardTooHigh() public {
        vm.prank(owner);
        staker.addReward(
            address(rewardToken), 
            address(owner), 
            3*WEEK
        );
        vm.expectRevert(MultiRewardsDistributor.SupplyMustBeGreaterThanZero.selector);
        vm.prank(owner);
        staker.notifyRewardAmount(address(rewardToken), 1e18);

        depositStake();

        vm.expectRevert(MultiRewardsDistributor.Unauthorized.selector);
        staker.notifyRewardAmount(address(rewardToken), 0);

        vm.startPrank(owner);
        vm.expectRevert(MultiRewardsDistributor.MustBeGreaterThanZero.selector);
        staker.notifyRewardAmount(address(rewardToken), 0);

        deal(address(rewardToken), address(owner), 10_000e18);
        staker.notifyRewardAmount(address(rewardToken), 10_000e18);

        vm.stopPrank();
        // vm.startPrank(owner);
        // staker.addReward(address(rewardToken), owner, 3*WEEK);
        // rewardToken.approve(address(staker), type(uint256).max);
        // staker.notifyRewardAmount(address(rewardToken), 1e18);
    }

    function test_setRewardsDistributor() public {
        vm.prank(owner);
        staker.addReward(
            address(rewardToken), 
            address(owner), 
            3*WEEK
        );
    
        vm.expectRevert("!core");
        staker.setRewardsDistributor(address(rewardToken), address(user1));

        vm.prank(owner);
        staker.setRewardsDistributor(address(rewardToken), address(user1));

        (address rewardsDistributor, , , , , ) = staker.rewardData(address(rewardToken));
        assertEq(rewardsDistributor, address(user1));

    }

    function test_recoverERC20() public {
        depositStake();
        deal(address(stakingToken), address(user1), 1e18);
        vm.prank(user1);
        stakingToken.transfer(address(staker), 1e18);

        vm.prank(owner);
        staker.addReward(address(rewardToken), owner, 3*WEEK);

        assertGt(stakingToken.balanceOf(address(staker)), staker.totalSupply());

        uint256 balance = stakingToken.balanceOf(address(staker));
        vm.prank(owner);
        staker.recoverERC20(address(stakingToken), 1e18);
        assertLt(stakingToken.balanceOf(address(staker)), balance);

        sweepToken.mint(address(staker), 1e18);
        assertEq(sweepToken.balanceOf(address(staker)), 1e18);
        vm.prank(owner);
        staker.recoverERC20(address(sweepToken), 1e18);
        assertEq(sweepToken.balanceOf(address(staker)), 0);

        deal(address(rewardToken), address(staker), 1e18);
        assertEq(rewardToken.balanceOf(address(staker)), 1e18);
        vm.prank(owner);
        staker.recoverERC20(address(rewardToken), 1e18);
        assertEq(rewardToken.balanceOf(address(staker)), 1e18); // Can't sweep reward token
    }

    function test_setRewardsDuration() public {
        depositStake();

        vm.prank(owner);
        staker.addReward(
            address(rewardToken), 
            address(owner), 
            3*WEEK
        );

        vm.expectRevert(MultiRewardsDistributor.Unauthorized.selector);
        staker.setRewardsDuration(address(rewardToken), 3*WEEK);

        vm.startPrank(owner);
        vm.expectRevert(MultiRewardsDistributor.MustBeGreaterThanZero.selector);
        staker.setRewardsDuration(address(rewardToken), 0);

        staker.setRewardsDuration(address(rewardToken), WEEK);

        staker.notifyRewardAmount(address(rewardToken), 1e18);

        vm.expectRevert(MultiRewardsDistributor.RewardsStillActive.selector);
        staker.setRewardsDuration(address(rewardToken), WEEK);

        skip(WEEK+1);
        staker.setRewardsDuration(address(rewardToken), WEEK);
    }

    function test_basicOperation() public {
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        mintGovToken(user1, amount);
        assertGt(stakingToken.balanceOf(user1), 0);

        // stake our assets
        vm.startPrank(user1);
        vm.expectRevert(GovStaker.InvalidAmount.selector);
        staker.stake(user1, 0);
        stakingToken.approve(address(staker), type(uint256).max);
        staker.stake(user1, amount);
        vm.stopPrank();
        assertEq(staker.balanceOf(user1), amount);

        // airdrop some token to use for rewards
        airdrop(rewardToken, owner, 10e18);
        
        // will revert if we haven't added it first
        vm.expectRevert(MultiRewardsDistributor.Unauthorized.selector);
        staker.notifyRewardAmount(address(rewardToken), 1e18);

        // add token to rewards array
        vm.startPrank(owner);
        staker.addReward(address(rewardToken), owner, 3*WEEK);
        rewardToken.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken), 1e18);
        vm.stopPrank();

        // only owner can setup rewards
        vm.expectRevert("!core");
        vm.prank(user1);
        staker.addReward(address(rewardToken), owner, WEEK);

        // check how much rewards we have for the week
        uint256 firstWeekRewards = staker.getRewardForDuration(
            address(rewardToken)
        );
        assertGt(firstWeekRewards, 0);

        // sleep to earn some profits
        skip(1 weeks);

        // check earnings, get reward
        uint256 earned = staker.earned(user1, address(rewardToken));
        assertGt(earned, 0);
        vm.prank(user1);
        staker.getOneReward(user1, address(rewardToken));
        vm.prank(user1);
        staker.getReward();
        assertGe(rewardToken.balanceOf(user1), earned);
        uint256 currentProfits = rewardToken.balanceOf(user1);

        // can't withdraw zero
        vm.startPrank(user1);
        vm.expectRevert(GovStaker.InvalidAmount.selector);
        staker.cooldown(user1, 0);

        // user withdraws ~half of their assets
        staker.cooldown(user1, amount / 2);

        // sleep to earn some profits
        skip(86400);

        // user fully exits
        assertGt(staker.balanceOf(user1), 0, "ABC");

        staker.exit(user1);
        uint256 totalGains = rewardToken.balanceOf(user1);
        assertGt(totalGains, currentProfits);
        assertEq(staker.balanceOf(user1), 0);
    }

    function test_multipleRewards() public {
        uint256 startLength = staker.rewardTokensLength();
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        mintGovToken(user1, amount);
        assertGt(stakingToken.balanceOf(user1), 0);

        // stake our assets
        vm.startPrank(user1);
        vm.expectRevert(GovStaker.InvalidAmount.selector);
        staker.stake(user1, 0);
        stakingToken.approve(address(staker), type(uint256).max);
        staker.stake(user1, amount);
        vm.stopPrank();
        assertEq(staker.balanceOf(user1), amount);

        // airdrop some token to use for rewards
        airdrop(rewardToken, owner, 10e18);
        airdrop(rewardToken2, owner, 1_000e18);
        vm.startPrank(owner);

        // add token to rewards array
        staker.addReward(address(rewardToken), owner, 2 * 1 weeks);
        rewardToken.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken), 1e18);

        // can't add the same token
        vm.expectRevert(MultiRewardsDistributor.RewardAlreadyAdded.selector);
        staker.addReward(address(rewardToken), owner, 3 * 1 weeks);

        // can't adjust duration while we're in progress
        vm.expectRevert(MultiRewardsDistributor.RewardsStillActive.selector);
        staker.setRewardsDuration(address(rewardToken), 3* 1 weeks);

        // can't add zero address
        vm.expectRevert(MultiRewardsDistributor.ZeroAddress.selector);
        staker.addReward(address(rewardToken), address(0), 3 * 1 weeks);
        vm.expectRevert(MultiRewardsDistributor.ZeroAddress.selector);
        staker.addReward(address(0), owner, WEEK);

        // add second token
        // duration must be >0
        vm.expectRevert(MultiRewardsDistributor.MustBeGreaterThanZero.selector);
        staker.addReward(address(rewardToken2), owner, 0);
        staker.addReward(address(rewardToken2), owner, 3 * 1 weeks);
        rewardToken2.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken2), 100e18);
        vm.stopPrank();

        // check reward token length
        uint256 length = staker.rewardTokensLength();
        assertEq(length, 2 + startLength);

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
        skip(staker.epochLength());

        // Assert that user with current earned rewards + realized balance gets rewards upon exit
        (GovStaker.AccountData memory acctData, ) = staker.checkpointAccount(user1);
        earned = staker.earned(user1, address(rewardToken2));
        assertGt(staker.balanceOf(user1), 0);
        assertGt(acctData.realizedStake, 0);
        assertGt(earned, 0);

        vm.expectEmit(true, true, true, true);
        emit RewardPaid(user1, address(rewardToken2), user1, earned);
        staker.exit(user1);

        (uint120 _realizedStake,,,) = staker.accountData(user1);
        assertEq(_realizedStake, 0);
        uint256 totalGainsTwo = rewardToken2.balanceOf(user1);
        assertGt(totalGainsTwo, currentProfitsTwo);
        assertEq(staker.balanceOf(user1), 0);
        vm.stopPrank();
    }

    function test_extendRewards() public {
        uint256 startLength = staker.rewardTokensLength();
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        mintGovToken(user1, amount);
        assertGt(stakingToken.balanceOf(user1), 0);

        // stake our assets
        vm.startPrank(user1);
        stakingToken.approve(address(staker), type(uint256).max);
        staker.stake(user1, amount);
        vm.stopPrank();
        assertEq(staker.balanceOf(user1), amount);

        // airdrop some token to use for rewards
        airdrop(rewardToken, owner, 10e18);
        airdrop(rewardToken2, owner, 1_000e18);
        vm.startPrank(owner);

        // add token to rewards array
        staker.addReward(address(rewardToken), owner, WEEK);
        rewardToken.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken), 1e18);

        // add second token
        staker.addReward(address(rewardToken2), owner, WEEK);
        rewardToken2.approve(address(staker), type(uint256).max);
        staker.notifyRewardAmount(address(rewardToken2), 100e18);
        vm.stopPrank();

        // check reward token length
        uint256 length = staker.rewardTokensLength();
        assertEq(length, 2 + startLength);

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
        vm.prank(owner);
        staker.notifyRewardAmount(address(rewardToken), 1e18);
        uint256 firstWeekRewardsCheckTwo = staker.getRewardForDuration(
            address(rewardToken)
        );
        uint256 firstWeekRewards2CheckTwo = staker.getRewardForDuration(
            address(rewardToken2)
        );
        assertEq(firstWeekRewards2, firstWeekRewards2CheckTwo);
        assertGt(firstWeekRewardsCheckTwo, firstWeekRewards);

    }


    function test_multiUserMultiRewards() public {
        // Here we should have multiple users, each with different amount
        // we rewards over time at an irregular interval, and also simulate
        // irregular staking and unstaking to make sure that at the end, all
        // rewards are distributed.
        assertEq(rewardToken.balanceOf(address(staker)), 0);
        assertEq(rewardToken2.balanceOf(address(staker)), 0);

        uint amountToStake = 100 * 10 ** 18;

        addRewards(address(rewardToken));
        addRewards(address(rewardToken2));

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256 i;
        for (; i < 20; i++) { // 20 weeks
            for (uint256 x = 0; x < users.length; x++) {
                uint bal = staker.balanceOf(users[x]);
                if (i > 0 && i % 5 == 0 && x == 1) {
                    vm.prank(users[x]);
                    staker.exit(users[x]);
                }
                if (i % 2 == 0 || x > 0) {
                    vm.prank(users[x]);
                    staker.stake(users[x], amountToStake / (x + 1));
                }
                if (bal > 0) {
                    staker.checkpointAccount(users[x]);
                    (uint120 _realizedStake,,,) = staker.accountData(users[x]);
                    if (_realizedStake > 0) {
                        vm.prank(users[x]);
                        staker.cooldown(users[x], bal / (x + 2));
                    }
                }
                if (i % 2 == 0) airdropAndNotify(address(rewardToken2), 500e20);
                airdropAndNotify(address(rewardToken), 250e20);
            }
            skip(1 weeks);
        }

        skip(10 weeks);

        uint ts = staker.totalSupply();
        uint totalStaked;
        // check that the rewards are distributed correctly
        for (uint256 x = 0; x < users.length; x++) {
            totalStaked += staker.balanceOf(users[x]);
            uint before1 = rewardToken.balanceOf(users[x]);
            uint before2 = rewardToken2.balanceOf(users[x]);
            uint earned1 = staker.earned(users[x], address(rewardToken));
            uint earned2 = staker.earned(users[x], address(rewardToken2));
            vm.prank(users[x]);
            staker.getReward();
            uint gain1 = rewardToken.balanceOf(users[x]) - before1;
            uint gain2 = rewardToken2.balanceOf(users[x]) - before2;
            assertEq(earned1, gain1);
            assertEq(earned2, gain2);
            assertEq(staker.earned(users[x], address(rewardToken)), 0);
            assertEq(staker.earned(users[x], address(rewardToken2)), 0);
        }
        assertEq(totalStaked, ts);
        // check that the rewards are gone
        uint dust = 1e8;
        assertLt(rewardToken.balanceOf(address(staker)), dust); // allow some dust
        assertLt(rewardToken2.balanceOf(address(staker)), dust); // allow some dust
    }

    function addRewards(address _token) public {
        vm.prank(owner);
        staker.addReward(_token, owner, 1 weeks);
        rewardToken.approve(address(staker), type(uint256).max);
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        MockToken(address(_asset)).mint(_to, _amount);
    }

    // Helpers
    function airdropAndNotify(address _asset, uint256 _amount) public {
        (
            address rewardsDistributor, // address with permission to update reward amount.
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored
        ) = staker.rewardData(_asset);
        address distributor =  rewardsDistributor;
        MockToken(_asset).mint(distributor, _amount);
        vm.prank(distributor);
        staker.notifyRewardAmount(_asset, _amount);
    }

    function mintGovToken(address _to, uint256 _amount) public {
        vm.prank(stakingToken.minter());
        stakingToken.mint(_to, _amount);
    }

    function test_ClaimOnBehalf() public {
        depositStake();
        addReward();
        skip(1 weeks);
        uint startBalance = rewardToken.balanceOf(user1);
        staker.getReward(user1); // call from different address
        assertGt(rewardToken.balanceOf(user1), startBalance);

        skip(1 weeks);
        startBalance = rewardToken.balanceOf(user1);
        staker.getOneReward(user1, address(rewardToken)); // call from different address
        assertGt(rewardToken.balanceOf(user1), startBalance);
    }

    function test_Redirect() public {
        depositStake();
        addReward();
        skip(1 weeks);
        vm.prank(user1);
        staker.setRewardRedirect(user2);
        uint startBalance = rewardToken.balanceOf(user2);
        staker.getReward(user1); // call from different address
        assertGt(rewardToken.balanceOf(user2), startBalance);

        skip(1 weeks);
        startBalance = rewardToken.balanceOf(user2);
        staker.getOneReward(user1, address(rewardToken)); // call from different address
        assertGt(rewardToken.balanceOf(user2), startBalance);

        vm.prank(user1);
        staker.setRewardRedirect(address(0)); // clear redirect

        skip(1 weeks);
        startBalance = rewardToken.balanceOf(user2);
        uint user1Balance = rewardToken.balanceOf(user1);
        staker.getOneReward(user1, address(rewardToken)); // call from different address
        assertEq(rewardToken.balanceOf(user2), startBalance);
        assertGt(rewardToken.balanceOf(user1), user1Balance);
    }

    function depositStake() public {
        uint256 amount = 1_000e18;
        mintGovToken(user1, amount);
        assertGt(stakingToken.balanceOf(user1), 0);
        vm.startPrank(user1);
        stakingToken.approve(address(staker), type(uint256).max);
        staker.stake(user1, amount);
        vm.stopPrank();
    }

    function addReward() public {
        deal(address(rewardToken), address(owner), 1_000_000e18);
        vm.prank(owner);
        staker.addReward(
            address(rewardToken), 
            address(owner), 
            3*WEEK
        );
        vm.prank(owner);
        staker.notifyRewardAmount(address(rewardToken), 1_000_000e18);
    }
}
