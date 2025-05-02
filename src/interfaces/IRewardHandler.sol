// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRewardHandler{
    function checkNewRewards(address _pair) external;
    function claimRewards(address _pair) external;
    function claimInsuranceRewards() external;
    function setPairWeight(address _pair, uint256 _amount) external;
    function queueInsuranceRewards() external;
    function queueStakingRewards() external;
    function pairEmissions() external view returns(address);
    function insuranceEmissions() external view returns(address);
    function insuranceRevenue() external view returns(address);
    function debtEmissionsReceiver() external view returns(address);
    function insuranceEmissionReceiver() external view returns(address);
}
