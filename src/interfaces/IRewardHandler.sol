// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRewardHandler{
    event BaseMinimumWeightSet(uint256 bweight);
    event MinimumWeightSet(address indexed user, uint256 mweight);
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
    function priceWatcher() external view returns(address);
    function feeLogger() external view returns(address);
    function pairTimestamp(address _pair) external view returns(uint256);
    function minimumWeights(address _pair) external view returns(uint256);
    function migrateState(address _oldRewardHandler, bool _migrateTimestamp, bool _migrateMinWeights) external;
    function stateMigrated() external view returns(bool);
    function baseMinimumWeight() external view returns(uint256);
    function setBaseMinimumWeight(uint256 _bweight) external;
    function getPairRate(address _pair, uint256 _timespan, uint256 _amount) external view returns(uint256);
    function setPairMinimumWeight(address _account, uint256 _amount) external;
}
