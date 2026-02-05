// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFraxLoan {
    function getFraxloan(address asset, uint256 amount, bytes calldata data) external;
    function calcFee(uint256 amount) external view returns (uint256);
    function isExempt(address user) external view returns (bool);
    function onlyWhitelist() external view returns (bool);
    function whitelistSetter() external view returns (address);
    function timelockAddress() external view returns (address);
    function setExempt(address user, bool value) external;
}

interface IFraxLoanCallback {
    function onFraxLoan(address asset, uint256 amount, bytes calldata data) external;
}
