// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRetentionIncentives {
    // Events
    event RewardAdded(uint256 reward);
    event WeightSet(address indexed user, uint256 oldWeight, uint256 newWeight);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRedirected(address indexed user, address redirect);
    event Finalize();
    event SetRewardHandler(address indexed handler);

    // View functions
    function duration() external view returns (uint256);
    function rewardToken() external view returns (IERC20);
    function registry() external view returns (address);
    function insurancePool() external view returns (address);
    function periodFinish() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function rewardPerTokenStored() external view returns (uint256);
    function queuedRewards() external view returns (uint256);
    function currentRewards() external view returns (uint256);
    function historicalRewards() external view returns (uint256);
    function isFinalized() external view returns (bool);
    function rewardHandler() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function userRewardPerTokenPaid(address _account) external view returns (uint256);
    function rewards(address _account) external view returns (uint256);
    function originalBalanceOf(address _account) external view returns (uint256);
    function rewardRedirect(address _account) external view returns (address);
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function earned(address _account) external view returns (uint256);

    // State changing functions
    function setRewardHandler(address _handler) external;
    function setAddressBalances(address[] calldata _addressList, uint256[] calldata _balanceList) external;
    function checkpoint_multiple(address[] calldata _accounts) external;
    function user_checkpoint(address _account) external;
    function setRewardRedirect(address _to) external;
    function getReward() external;
    function getReward(address _account) external;
    function getReward(address _account, address _forwardTo) external;
    function donate(uint256 _amount) external returns (bool);
    function queueNewRewards(uint256 _rewards) external returns (bool);
}
