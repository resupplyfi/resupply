// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/dao/GovStaker.sol";
import "../../src/dao/GovStakerEscrow.sol";
import {IGovStakerEscrow} from "../../src/interfaces/IGovStakerEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract GovStakerTest is Test {
    GovStaker staker;
    GovStakerEscrow escrow;
    MockERC20 token;
    address deployer;
    address user1;
    uint256 public constant EPOCH_LENGTH = 60 * 60 * 24 * 2;
    uint256 public constant MAX_STAKE_GROWTH_EPOCHS = 3;

    function setUp() public {
        deployer = address(this);
        user1 = address(0x1);

        token = new MockERC20();
        uint256 nonce = vm.getNonce(deployer);
        address escrowAddress = computeCreateAddress(deployer, nonce);
        address govStakingAddress = computeCreateAddress(deployer, nonce + 1);
        escrow = new GovStakerEscrow(govStakingAddress, address(token));
        staker = new GovStaker(
            address(token),    // stakeToken
            EPOCH_LENGTH,      // EPOCH_LENGTH
            MAX_STAKE_GROWTH_EPOCHS,    // MAX_STAKE_GROWTH_EPOCHS
            block.timestamp,   // START_TIME
            deployer,          // owner
            IGovStakerEscrow(escrowAddress) // Escrow
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
        assertEq(staker.getAccountWeight(user1), 0, "Weight should be 0");
        vm.warp(block.timestamp + EPOCH_LENGTH); // Test weight increase
        assertEq(staker.getAccountWeight(user1), amountToStake, "Weight should be 0");
        vm.warp(block.timestamp + (MAX_STAKE_GROWTH_EPOCHS - 1) * EPOCH_LENGTH); // Test weight increase
        assertEq(staker.getAccountWeight(user1), amountToStake * MAX_STAKE_GROWTH_EPOCHS, "Weight should be 0");

        vm.warp(block.timestamp + warmupWait() * 100);
        staker.checkpointAccount(user1);
    }

    function testFailUnapprovedStake() public {
        vm.prank(user1);
        staker.stakeFor(deployer, 100 * 10 ** 18);
        // This should fail since user1 is not approved to stake for deployer
    }

    function _checkExpectedStake(address _account, uint expectedStake) internal {
        (GovStaker.AccountData memory acctData, ) = staker.checkpointAccount(_account);
        assertEq(acctData.realizedStake, expectedStake, "Stake should be updated correctly");
    }

    function testStakeAndUnstake() public {
        uint amountToStake = 50 * 10 ** 18;
        vm.startPrank(user1);
        staker.stake(amountToStake);
        assertEq(staker.balanceOf(user1), amountToStake, "Stake should be updated correctly");
        assertEq(token.balanceOf(address(staker)), amountToStake, "Tokens should be transferred to staker");
        vm.warp(block.timestamp + warmupWait()); // Warm up wait
        _checkExpectedStake(user1, amountToStake);

        // Initiate cooldown and unstake
        staker.cooldown(amountToStake);
        uint cooldownDuration = staker.cooldownDuration();
        vm.warp(block.timestamp + cooldownDuration);
        staker.unstake(user1);
        // staker.unstake(amountToStake, user1);
        vm.stopPrank();

        assertEq(staker.balanceOf(user1), 0, "Balance after unstake should be zero");
        assertEq(token.balanceOf(user1), 10000 * 10 ** 18, "Token should be returned to user");
    }

    function testUnstakeAmount() public {
        vm.startPrank(user1);
        uint amountToStake = 100 * 10 ** 18;
        staker.stake(amountToStake);
        vm.warp(block.timestamp + warmupWait()); // Warm up wait

        // Cooldown
        staker.cooldown(amountToStake);
        uint cooldownDuration = staker.cooldownDuration();
        vm.warp(block.timestamp + cooldownDuration);
        uint amount = staker.unstake(user1);
        assertEq(amount, amountToStake, "Unstake amount should be equal to staked amount");
        vm.stopPrank();
    }

    function warmupWait() internal view returns (uint) {
        return EPOCH_LENGTH * MAX_STAKE_GROWTH_EPOCHS;
    }

    function getEpoch() public view returns (uint) {
        return staker.getEpoch();
    }
}
