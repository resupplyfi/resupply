// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Canonical market registry interface for LlamaLend v2 factories.
interface ICurveLendV2Factory {
    struct Market {
        address vault;
        address controller;
        address amm;
        address collateralToken;
        address borrowedToken;
        address priceOracle;
        address monetaryPolicy;
    }

    function version() external view returns (string memory);

    function check_contract(address account) external view returns (uint256 marketIndex, uint256 contractType);

    function markets(uint256 marketIndex) external view returns (Market memory);
}
