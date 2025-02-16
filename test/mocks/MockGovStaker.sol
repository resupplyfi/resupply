// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { GovStaker } from "../../src/dao/staking/GovStaker.sol";

contract MockGovStaker is GovStaker {

    address immutable previousStaker;
    
    constructor(
        address _core,
        address _stakeToken, 
        uint24 _cooldownEpochs, 
        address _previousStaker
    ) GovStaker(_core, _stakeToken, _cooldownEpochs) {
        previousStaker = _previousStaker;
    }

    function onPermaStakeMigrate(address account) external override {
        require(msg.sender == previousStaker, "!migrate");
        accountData[account].isPermaStaker = true;
    }
}