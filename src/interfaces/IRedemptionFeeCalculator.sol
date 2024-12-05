// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IRedemptionFeeCalculator
/// @notice Interface for calculating redemption fees based on pair usage
interface IRedemptionFeeCalculator {
    /// @notice Struct to store redemption rate information for a pair
    struct RedemptionRateInfo {
        uint256 minuteDecayFactor;
        uint256 baseRate;
        uint64 lastFeeOperationTime;
        uint256 redemptionFeeFloor;
        uint256 maxRedemptionFee;
    }

    /// @notice Emitted when the base rate is updated
    event BaseRateUpdated(uint256 newBaseRate);
    
    /// @notice Emitted when the last fee operation time is updated
    event LastFeeOpTimeUpdated(uint256 newLastFeeOpTime);

    /// @notice Returns the redemption handler contract address
    function redemptionHandler() external view returns (address);

    /// @notice Returns the pair info for a specific pair
    /// @param pair The address of the pair to query
    /// @return RedemptionRateInfo struct containing pair's fee calculation parameters
    function pairInfo(address pair) external view returns (RedemptionRateInfo memory);

    /// @notice Returns the decimal precision used in calculations
    function DECIMAL_PRECISION() external view returns (uint256);

    /// @notice Returns the number of seconds in one minute
    function SECONDS_IN_ONE_MINUTE() external view returns (uint256);

    /// @notice Previews the redemption fee without updating state
    /// @param _pair The address of the pair being redeemed
    /// @param _amount The amount being redeemed
    /// @return The calculated redemption fee
    function previewRedemptionFee(address _pair, uint256 _amount) external returns (uint256);

    /// @notice Calculates and updates the redemption fee
    /// @param _pair The address of the pair being redeemed
    /// @param _amount The amount being redeemed
    /// @return The calculated redemption fee
    function updateRedemptionFee(address _pair, uint256 _amount) external returns (uint256);

    /// @notice Gets the current redemption rate for a pair
    /// @param _pair The address of the pair
    /// @return The current redemption rate
    function getRedemptionRate(address _pair) external view returns (uint256);

    /// @notice Gets the redemption rate with decay applied
    /// @param _pair The address of the pair
    /// @return The decayed redemption rate
    function getRedemptionRateWithDecay(address _pair) external view returns (uint256);

    /// @notice Calculates the redemption fee with decay
    /// @param _pair The address of the pair
    /// @param _debtRepaid The amount of debt being repaid
    /// @return The calculated redemption fee
    function getRedemptionFeeWithDecay(address _pair, uint256 _debtRepaid) external view returns (uint256);

    /// @notice Sets the default settings for new pairs
    /// @param _minuteDecayFactor The decay factor per minute
    /// @param _redemptionFeeFloor The minimum redemption fee
    /// @param _maxRedemptionFee The maximum redemption fee
    function setDefaultSettings(
        uint256 _minuteDecayFactor,
        uint256 _redemptionFeeFloor,
        uint256 _maxRedemptionFee
    ) external;
}