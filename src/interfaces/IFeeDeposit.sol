// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFeeDeposit {
    function operator() external view returns(address);
    function lastDistributedEpoch() external view returns(uint256);
    function setOperator(address _newAddress) external;
    function distributeFees() external;
    function incrementPairRevenue(uint256 _fees, uint256 _otherFees) external;
}