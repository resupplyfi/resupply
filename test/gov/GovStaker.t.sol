// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/dao/GovStaker.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract GovStakerTest is Test {
    GovStaker staker;
    MockERC20 token;
    address deployer;
    address user1;

    function setUp() public {
        deployer = address(this);
        user1 = address(0x1);

        token = new MockERC20();
        staker = new GovStaker(
            address(token),    // stakeToken
            1,                 // MAX_STAKE_GROWTH_WEEKS
            block.timestamp,   // START_TIME
            deployer           // owner
        );

        token.approve(address(staker), type(uint256).max);
        token.transfer(user1, 10000 * 10 ** 18);
        vm.prank(user1);
        token.approve(address(staker), type(uint256).max);
    }

    function testInitialDeployment() public {
        assertEq(staker.owner(), deployer, "Owner should be deployer");
        assertEq(address(staker.stakeToken()), address(token), "Stake token should be set correctly");
    }

    function testStake() public {
        uint amountToStake = 100 * 10 ** 18;
        vm.prank(user1);
        staker.stake(amountToStake);
        assertEq(staker.balanceOf(user1), amountToStake, "Stake balance should be updated");
        assertEq(token.balanceOf(address(staker)), amountToStake, "Token should be transferred to staker");
    }

    function testFailUnapprovedStake() public {
        vm.prank(user1);
        staker.stakeFor(deployer, 100 * 10 ** 18);
        // This should fail since user1 is not approved to stake for deployer
    }

    function _checkExpectedStake(address _account, uint expectedStake) internal {
        (GovStaker.AccountData memory acctData, uint weight) = staker.checkpointAccount(_account);
        console.log("acctData.realizedStake", acctData.realizedStake);
        console.log("weight", weight);
        console.log("balance", staker.balanceOf(_account));
        assertEq(acctData.realizedStake, expectedStake, "Stake should be updated correctly");
    }

    function testStakeAndUnstake() public {
        uint amountToStake = 50 * 10 ** 18;
        vm.startPrank(user1);
        staker.stake(amountToStake);
        assertEq(staker.balanceOf(user1), amountToStake, "Stake should be updated correctly");
        assertEq(token.balanceOf(address(staker)), amountToStake, "Tokens should be transferred to staker");
        vm.warp(block.timestamp + 1 weeks);
        _checkExpectedStake(user1, amountToStake);
        staker.unstake(amountToStake, user1);
        vm.stopPrank();

        assertEq(staker.balanceOf(user1), 0, "Balance after unstake should be zero");
        assertEq(token.balanceOf(user1), 10000 * 10 ** 18, "Token should be returned to user");
    }

    function testFailUnstakeMoreThanStaked() public {
        vm.prank(user1);
        staker.stake(100 * 10 ** 18);
        vm.expectRevert("insufficient stake available");
        staker.unstake(200 * 10 ** 18, user1);
    }

    // More tests for edge cases and permissions...
}