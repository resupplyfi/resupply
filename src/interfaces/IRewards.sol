// SPDX-License-Identifier: ISC
pragma solidity >=0.8.19;

interface IRewards{
    function rewardToken() external view returns(address);
    function periodFinish() external view returns(uint256);
    function rewardRate() external view returns(uint256);
    function totalSupply() external view returns(uint256);
    function balanceOf(address _account) external view returns(uint256);
    function queueNewRewards(uint256 _rewards) external returns(bool);
    function setWeight(address _account, uint256 _amount) external returns(bool);
    function setWeights(address[] calldata _account, uint256[] calldata _amount) external;
    function getReward() external;
    function getReward(address _account) external;
    function getReward(address _account, address _forwardTo) external;
    function setRewardRedirect(address _to) external;
    function user_checkpoint(address _account) external;
}
