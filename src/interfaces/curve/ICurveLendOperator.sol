// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveLendOperator{
    function withdraw_profit() external;
    function profit() external view returns(uint256);
    function mintLimit() external view returns(uint256);
    function mintedAmount() external view returns(uint256);
}