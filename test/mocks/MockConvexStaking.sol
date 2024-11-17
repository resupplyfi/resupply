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

    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool) {
        balances[msg.sender] += _amount;
        PoolInfo memory _poolInfo = poolInfo[_pid];
        IERC20(_poolInfo.lpToken).transferFrom(msg.sender, address(this), _amount);
        if (_stake) {
            MockConvexRewards(_poolInfo.rewards).stake(_amount);
        }
        return true;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return balances[_account];
    }

    function addPool(address _lpToken) external returns (uint256) {
        uint256 _pid = lpToPid[_lpToken];
        if (_pid != 0) return _pid;
        _pid = ++pid;
        lpToPid[_lpToken] = _pid;
        address _rewards = address(new MockConvexRewards(_pid, _lpToken, address(0)));
        poolInfo[_pid] = PoolInfo({
            lpToken: _lpToken,
            gauge: address(0),
            rewards: _rewards,
            shutdown: false
        });
        IERC20(_lpToken).approve(_rewards, type(uint256).max);
        return _pid;
    }

    function getPoolInfo(uint256 _pid) external view returns (PoolInfo memory) {
        return poolInfo[_pid];
    }
}
