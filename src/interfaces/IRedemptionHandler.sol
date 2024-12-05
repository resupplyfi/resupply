// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRedemptionHandler {
    // Events
    event SetBaseRedemptionFee(uint256 _fee);

    // View Functions
    function registry() external view returns (address);
    function debtToken() external view returns (address);
    function baseRedemptionFee() external view returns (uint256);
    function PRECISION() external view returns (uint256);

    // State-Changing Functions
    function setBaseRedemptionFee(uint256 _fee) external;

    // View Functions for Redemption Calculations
    function getMaxRedeemableCollateral(address _pair) external view returns (uint256);
    function getMaxRedeemableValue(address _pair) external view returns (uint256);
    function getMaxRedeemableUnderlying(address _pair) external view returns (uint256);
    function getRedemptionFeePct(address _pair, uint256 _amount) external view returns (uint256);

    // Main Redemption Function
    function redeemFromPair(
        address _pair,
        uint256 _amount,
        uint256 _maxFeePct,
        address _receiver,
        bool _redeemToUnderlying
    ) external returns (uint256);
}
