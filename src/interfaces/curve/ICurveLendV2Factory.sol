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

    function market_count() external view returns (uint256);

    function check_contract(address account) external view returns (uint256 marketIndex, uint256 contractType);

    function markets(uint256 marketIndex) external view returns (Market memory);
}

/// @notice Lender-vault getters used to cross-check a LlamaLend v2 market tuple.
interface ICurveLendV2Vault {
    function factory() external view returns (address);

    function asset() external view returns (address);

    function borrowed_token() external view returns (address);

    function collateral_token() external view returns (address);

    function controller() external view returns (address);

    function amm() external view returns (address);
}
