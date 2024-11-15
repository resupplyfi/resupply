// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockConvexRewards {

    IERC20 public rewardToken;
    IERC20 public stakingToken;
    uint256 public constant duration = 7 days;

    uint256 public pid;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public queuedRewards = 0;
    uint256 public currentRewards = 0;
    uint256 public historicalRewards = 0;
    uint256 public constant newRewardRatio = 830;
    uint256 private _totalSupply;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(
        uint256 pid_,
        address stakingToken_,
        address rewardToken_
    ) {
        pid = pid_;
        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 _amount) public returns(bool) {
        _balances[msg.sender] += _amount;
        IERC20(stakingToken).transferFrom(msg.sender, address(this), _amount);
        return true;
    }

    function withdraw(uint256 _amount) public returns(bool) {
        _balances[msg.sender] -= _amount;
        IERC20(stakingToken).transfer(msg.sender, _amount);
        return true;
    }

    function withdrawAndUnwrap(uint256 _amount, bool _claim) public returns(bool){
        _balances[msg.sender] -= _amount;
        IERC20(stakingToken).transfer(msg.sender, _amount);
        return true;
    }

    function getReward() public returns(bool) {
        // Implementation for getReward function
        return true;
    }

    function exit() public returns(bool) {
        // Implementation for exit function
        return true;
    }
}
