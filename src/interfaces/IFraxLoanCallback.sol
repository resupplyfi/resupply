// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFraxLoanCallback {
    function onFraxLoan(address asset, uint256 amount, bytes calldata data) external;
}
