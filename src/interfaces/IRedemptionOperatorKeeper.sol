// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Narrow keeper-facing ABI for redemption discovery and execution.
interface IRedemptionOperatorKeeper {
    function isProfitable(uint256 notionalWad) external view returns (address bestPair, uint256 expectedProfit, uint256 redeemAmount, uint8 routeId, address loanAsset, uint256 loanAmount);

    function executeRedemption(address bestPair, uint8 routeId, uint256 loanAmount, uint256 minReusdFromSwap, uint256 minProfit, uint256 maxFeePct) external;
}
