// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ResupplyPairConstants
 * @notice Based on code from Drake Evans and Frax Finance's pair constants (https://github.com/FraxFinance/fraxlend), adapted for Resupply Finance
 */

abstract contract ResupplyPairConstants {

    // Precision settings
    uint256 public constant LTV_PRECISION = 1e5; // 5 decimals
    uint256 public constant LIQ_PRECISION = 1e5;
    uint256 public constant EXCHANGE_PRECISION = 1e18;
    uint256 public constant RATE_PRECISION = 1e18;
    uint256 public constant SHARE_REFACTOR_PRECISION = 1e12;
    uint256 public constant PAIR_DECIMALS = 1e18;
}
