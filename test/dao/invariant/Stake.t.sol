// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22 <0.9.0;

import { Setup } from "../../Setup.sol";
import { StakeHandler } from "./handlers/StakeHandler.sol";
import { GovStaker } from "src/dao/staking/GovStaker.sol";

contract Stake_Invariant_Test is Setup {

    StakeHandler internal stakeHandler;

    function setUp() public virtual override {
        super.setUp();

        // Deploy the StakeHandler.
        stakeHandler = new StakeHandler({ _govStaker: staker });
        deal(address(govToken), address(stakeHandler), 100_000_000e18);

        // Label the contracts.
        vm.label({ account: address(stakeHandler), newLabel: "StakeHandler" });

        // Target the StakeHandler for invariant testing.
        targetContract(address(stakeHandler));

        // Prevent these contracts from being fuzzed as `msg.sender`.
        excludeSender(address(stakeHandler));
    }

    function invariant_BalanceIsSumOfPendingAndRealized() external {
        (GovStaker.AccountData memory acctData, ) = staker.checkpointAccount(address(stakeHandler));
        uint256 balance = staker.balanceOf(address(stakeHandler));
        uint256 totalPending = acctData.pendingStake;
        assertEq(
            balance, 
            acctData.pendingStake + acctData.realizedStake, 
            "Invariant violated: balance is not sum of pending and realized"
        );
    }

    function invariant_WeightIsLessThanOrEqualToRealizedStake() external {
        (GovStaker.AccountData memory acctData, ) = staker.checkpointAccount(address(stakeHandler));
        uint256 weight = staker.getAccountWeight(address(stakeHandler));
        assertLe(weight, acctData.realizedStake, "Invariant violated: weight is greater than realized stake");
        assertLe(weight, staker.balanceOf(address(stakeHandler)), "Invariant violated: weight is greater than balance");
    }

    function invariant_AmountIsSumOfUnstakableAndCooldownAmount() external {
        uint256 weight = staker.getAccountWeight(address(stakeHandler));
        uint256 balance = staker.balanceOf(address(stakeHandler));
        (, uint152 amount) = staker.cooldowns(address(stakeHandler));
        balance += uint256(amount);
        assertGe(balance, weight, "Invariant violated: weight is greater than balance + cooldown amount");
    }
}