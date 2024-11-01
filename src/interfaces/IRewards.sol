// SPDX-License-Identifier: ISC
pragma solidity >=0.8.19;

interface IRewards{
    struct EarnedData {
        address token;
        uint256 amount;
    }

    function rewardMap(address _token) external view returns(uint256 slot);
    function rewards(uint256 index) external view returns(address reward_token, uint256 reward_remaining, bool is_non_claimable);
    function rewardToken() external view returns(address);
    function periodFinish() external view returns(uint256);
    function rewardRate() external view returns(uint256);
    function totalSupply() external view returns(uint256);
    function balanceOf(address _account) external view returns(uint256);
    function queueNewRewards(uint256 _rewards) external returns(bool);
    function notifyRewardAmount(address _rewardsToken, uint256 _rewardAmount) external;
    function setMinimumWeight(address _account, uint256 _amount) external;
    function setWeight(address _account, uint256 _amount) external returns(bool);
    function setWeights(address[] calldata _account, uint256[] calldata _amount) external;
    function getReward() external;
    function getReward(address _account) external;
    function getReward(address _account, address _forwardTo) external;
    function setRewardRedirect(address _to) external;
    function user_checkpoint(address _account) external;
    function earned(address _account) external returns(EarnedData[] memory claimable);
}
