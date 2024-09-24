// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFeeDeposit {
    function operator() external view returns(address);
    function setOperator(address _newAddress) external;
    function distributeFees(address _to, uint256 _amount) external;
    function incrementPairRevenue(uint256 _amount) external;
}