// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

interface IRewardHandler{
    function checkNewRewards(address _pair) external;
    function claimRewards(address _pair) external;
    function claimInsuranceRewards() external;
    function setPairWeight(address _pair, uint256 _amount) external;
    function queueInsuranceRewards() external;
}
