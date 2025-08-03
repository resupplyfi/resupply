// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IFeeLogger
/// @notice Interface for FeeLogger
interface IFeeLogger {
    function updateTotalFees(uint256 _epoch, uint256 _amount) external;
    function updateInterestFees(address _pair, uint256 _epoch, uint256 _amount) external;
    function logTotalFees(uint256 _epoch, uint256 _amount) external;
    function logInterestFees(address _pair, uint256 _epoch, uint256 _amount) external;
    function pairEpochWeightings(address _pair, uint256 _epoch) external view returns(uint256 _interestFees);
    function epochInterestFees(uint256 _epoch) external view returns(uint256 _fees);
}