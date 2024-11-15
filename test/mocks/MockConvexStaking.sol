// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockConvexRewards } from "test/mocks/MockConvexRewards.sol";

contract MockConvexStaking {
    struct PoolInfo {
        address lpToken;
        address gauge;
        address rewards;
        bool shutdown;
    }

    uint256 public pid;
    mapping(uint256 => PoolInfo) public poolInfo;
    mapping(address => uint256) public balances;
    mapping(address lp => uint256 pid) public lpToPid;

    function setPoolInfo(
        uint256 _pid,
        address _lpToken,
        address _gauge,
        address _rewards,
        bool _shutdown
    ) external {
        poolInfo[_pid] = PoolInfo({
            lpToken: _lpToken,
            gauge: _gauge,
            rewards: _rewards,
            shutdown: _shutdown
        });
    }

    function deposit(uint256 _pid, uint256 _amount, bool _stake) external {
        balances[msg.sender] += _amount;
        address lptoken = poolInfo[_pid].lpToken;
        address rewards = poolInfo[_pid].rewards;
        IERC20(lptoken).transferFrom(msg.sender, rewards, _amount);
    }

    function balanceOf(address _account) external view returns (uint256) {
        return balances[_account];
    }

    function addPool(address _lpToken) external returns (uint256 pid) {
        uint256 pid = lpToPid[_lpToken];
        if (pid != 0) return pid;
        pid++;
        lpToPid[_lpToken] = pid;
        poolInfo[pid] = PoolInfo({
            lpToken: _lpToken,
            gauge: address(0),
            rewards: address(new MockConvexRewards(pid, _lpToken, address(0))),
            shutdown: false
        });
    }

    function getPoolInfo(uint256 _pid) external view returns (PoolInfo memory) {
        return poolInfo[_pid];
    }
}
