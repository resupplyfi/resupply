// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRedemptionOperator {
    function initialize(address manager, address[] calldata callers) external;
    function setApprovals() external;
    function setManager(address manager) external;
    function setApprovedCaller(address _caller, bool _status) external;
    function executeRedemption(
        address bestPair,
        uint256 flashAmount,
        uint256 minReusdFromSwap,
        uint256 minProfit,
        uint256 maxFeePct
    ) external;
    function isProfitable(uint256 flashAmount)
        external
        view
        returns (address bestPair, uint256 profit, uint256 redeemAmount);
    function sweep(address token, address to, uint256 amount) external;
    function approveRH() external;

    function approvedCallers(address caller) external view returns (bool);
    function manager() external view returns (address);
}
