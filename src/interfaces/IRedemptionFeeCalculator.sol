// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IRedemptionFeeCalculator
/// @notice Interface for calculating redemption fees based on pair usage
interface IRedemptionFeeCalculator {
    /// @notice Struct to store redemption rate information for a pair
    struct RedeemptionRateInfo {
        uint64 timestamp;
        uint192 usage;
    }

    /// @notice Returns the redemption handler contract address
    function redemptionHandler() external view returns (address);

    /// @notice Returns the rating data for a specific pair
    /// @param pair The address of the pair to query
    /// @return RedeemptionRateInfo struct containing timestamp and usage data
    function ratingData(address pair) external view returns (RedeemptionRateInfo memory);

    /// @notice Previews the redemption fee without updating state
    /// @param pair The address of the pair being redeemed
    /// @param amount The amount being redeemed
    /// @return The calculated redemption fee
    function previewRedemptionFee(address pair, uint256 amount) external view returns (uint256);

    /// @notice Calculates and updates the redemption fee
    /// @param pair The address of the pair being redeemed
    /// @param amount The amount being redeemed
    /// @return The calculated redemption fee
    /// @dev Can only be called by the redemption handler
    function updateRedemptionFee(address pair, uint256 amount) external returns (uint256);
}