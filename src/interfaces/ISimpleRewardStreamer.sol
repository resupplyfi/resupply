pragma solidity 0.8.28;

interface ISimpleRewardStreamer {
    error SafeERC20FailedOperation(address token);
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRedirected(address indexed user, address redirect);
    event WeightSet(address indexed user, uint256 oldWeight, uint256 newWeight);

    function balanceOf(address _account) external view returns (uint256);

    function core() external view returns (address);

    function currentRewards() external view returns (uint256);

    function donate(uint256 _amount) external returns (bool);

    function duration() external view returns (uint256);

    function earned(address _account) external view returns (uint256);

    function getReward() external;

    function getReward(address _account, address _forwardTo) external;

    function getReward(address _account) external;

    function historicalRewards() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function lastUpdateTime() external view returns (uint256);

    function owner() external view returns (address);

    function periodFinish() external view returns (uint256);

    function queueNewRewards(uint256 _rewards) external returns (bool);

    function queuedRewards() external view returns (uint256);

    function registry() external view returns (address);

    function rewardPerToken() external view returns (uint256);

    function rewardPerTokenStored() external view returns (uint256);

    function rewardRate() external view returns (uint256);

    function rewardRedirect(address) external view returns (address);

    function rewardToken() external view returns (address);

    function rewards(address) external view returns (uint256);

    function setRewardRedirect(address _to) external;

    function setWeight(address _account, uint256 _amount)
        external
        returns (bool);

    function setWeights(address[] memory _account, uint256[] memory _amount)
        external;

    function totalSupply() external view returns (uint256);

    function userRewardPerTokenPaid(address) external view returns (uint256);

    function user_checkpoint(address _account) external;
}