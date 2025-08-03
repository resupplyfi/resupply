// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IStakedFrax {
    struct RewardsCycleData {
        uint40 cycleEnd; // Timestamp of the end of the current rewards cycle
        uint40 lastSync; // Timestamp of the last time the rewards cycle was synced
        uint216 rewardCycleAmount; // Amount of rewards to be distributed in the current cycle
    }

    function rewardsCycleData() external view returns(RewardsCycleData memory);
    function storedTotalAssets() external view returns(uint256);
    function maxDistributionPerSecondPerAsset() external view returns(uint256);
    function priceFeedVault() external view returns(address);
    function syncRewardsAndDistribution() external;
    function updateVaultTknOracle() external;
    function setMintRedeemFee(uint256 _fee) external;
}