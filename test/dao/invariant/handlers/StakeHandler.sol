// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22 <0.9.0;

import { Test } from "lib/forge-std/src/Test.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { GovStaker } from "src/dao/staking/GovStaker.sol";
import { GovToken } from "src/dao/GovToken.sol";

contract StakeHandler is BaseHandler, Test {
    GovStaker internal govStaker;
    GovToken internal govToken;

    constructor(GovStaker _govStaker) {
        govStaker = _govStaker;
        govToken = GovToken(_govStaker.stakeToken());
        govToken.approve(address(govStaker), type(uint256).max);
    }

    uint constant MIN_STAKE_AMOUNT = 1;
    
    function stake(uint256 amount) external {
        amount = bound(amount, MIN_STAKE_AMOUNT, type(uint104).max);
        deal(address(govToken), address(this), amount);
        govStaker.stake(address(this), amount);
    }

    function cooldownMax() external {
        (GovStaker.AccountData memory acctData, ) = govStaker.checkpointAccount(address(this));
        if (acctData.realizedStake == 0) return;
        govStaker.cooldown(address(this), type(uint120).max);
    }

    function cooldownExact(uint256 amount) external {
        (GovStaker.AccountData memory acctData, ) = govStaker.checkpointAccount(address(this));
        if (acctData.realizedStake == 0) return;
        amount = bound(amount, 1, acctData.realizedStake);
        govStaker.cooldown(address(this), amount);
    }

    function unstakeAll() external {
        (uint104 end, ) = govStaker.cooldowns(address(this));
        if(
            uint104(block.timestamp) < end || 
            govStaker.cooldownEpochs() == 0
        ) return;

        govStaker.unstake(address(this), address(this));
    }

    function checkPointAndGetAccountData() external returns (GovStaker.AccountData memory acctData) {
        (acctData, ) = govStaker.checkpointAccount(address(this));
    }
}
