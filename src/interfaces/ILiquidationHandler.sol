// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ILiquidationHandler {
    function operator() external view returns(address);
    function setOperator(address _newAddress) external;
    function processLiquidationDebt(address _collateral, uint256 _debtAmount) external;
    function processCollateral(address _collateral) external;
    function liquidate(
        address _pair,
        address _borrower
    ) external returns (uint256 _collateralForLiquidator);
}