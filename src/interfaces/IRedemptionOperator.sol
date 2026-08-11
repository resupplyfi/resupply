// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IRedemptionOperatorKeeper } from "src/interfaces/IRedemptionOperatorKeeper.sol";

interface IRedemptionOperator is IRedemptionOperatorKeeper {
    function initialize(address manager, address[] calldata callers) external;
    function setApprovals() external;
    function revokeAllApprovals() external;
    function setManager(address manager) external;
    function setApprovedCaller(address caller, bool status) external;
    function sweep(address token, address to, uint256 amount) external;
    function approveRH() external;

    function approvedCallers(address caller) external view returns (bool);
    function manager() external view returns (address);
}
