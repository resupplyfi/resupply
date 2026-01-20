// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPrismaFactory {
    struct DeploymentParams {
        uint256 minuteDecayFactor;
        uint256 redemptionFeeFloor;
        uint256 maxRedemptionFee;
        uint256 borrowingFeeFloor;
        uint256 maxBorrowingFee;
        uint256 interestRateInBps;
        uint256 maxDebt;
        uint256 MCR;
    }

    function deployNewInstance(
        address collateral,
        address priceFeed,
        address customTroveManagerImpl,
        address customSortedTrovesImpl,
        DeploymentParams calldata params
    ) external;

    function troveManagerCount() external view returns (uint256);
    function troveManagers(uint256 index) external view returns (address);
}
