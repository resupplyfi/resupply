// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILiquidationHandler {
    function operator() external view returns(address);
    function setOperator(address _newAddress) external;
    function processCollateral(address _collateral, uint256 _collateralAmount, uint256 _debtAmount) external;
}