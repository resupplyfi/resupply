// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IFeeLogger
/// @notice Interface for FeeLogger
interface IFeeLogger {
    event LogTotalFees(uint256 _epoch, uint256 _amount);
    event LogInterestFees(address _pair, uint256 _epoch, uint256 _amount);
    function logTotalFees(uint256 _epoch, uint256 _amount) external;
    function logInterestFees(address _pair, uint256 _epoch, uint256 _amount) external;
    function pairEpochWeightings(address _pair, uint256 _epoch) external view returns(uint256 _interestFees);
    function epochInterestFees(uint256 _epoch) external view returns(uint256 _fees);
    function epochTotalFees(uint256 _epoch) external view returns(uint256 _fees);
    function registry() external view returns(address _registry);
}