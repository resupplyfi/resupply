// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRedemptionHandler {
    function baseRedemptionFee() external view returns(uint256);
    function ratingData(address _pair) external view returns(uint64 _timestamp, uint192 _usage);
    function totalWeight() external view returns(uint256);
    function getRedemptionFeePct(address _pair, uint256 _amount) external view returns(uint256);
    function redeemFromPair (
        address _pair,
        uint256 _amount,
        uint256 _maxFeePct,
        address _receiver,
        bool _redeemToUnderlying
    ) external returns(uint256);

    function previewRedeem(address _pair, uint256 _amount) external view returns(uint256 _returnedUnderlying, uint256 _returnedCollateral, uint256 _fee);
}