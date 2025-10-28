// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveLendController {
    /**
     * @notice Create loan
     * @param collateral Amount of collateral to use
     * @param debt Stablecoin debt to take
     * @param N Number of bands to deposit into (to do autoliquidation-deliquidation),
     *          can be from MIN_TICKS to MAX_TICKS
     * @param _for Address to create the loan for
     */
    function create_loan(uint256 collateral, uint256 debt, uint256 N, address _for) external;
}
