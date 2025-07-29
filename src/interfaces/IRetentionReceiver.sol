// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRetentionReceiver {
    // Events
    event TreasuryAllocationPerEpochSet(uint256 _treasuryAllocationPerEpoch);

    // View functions
    function emissionsController() external view returns (address);
    function registry() external view returns (address);
    function govToken() external view returns (IERC20);
    function name() external view returns (string memory);
    function retentionRewards() external view returns (address);
    function MAX_REWARDS() external view returns (uint256);
    function treasuryAllocationPerEpoch() external view returns (uint256);
    function distributedRewards() external view returns (uint256);
    function lastEpoch() external view returns (uint256);
    function getEpoch() external view returns (uint256);
    function getReceiverId() external view returns (uint256);
    function claimableEmissions() external view returns (uint256);

    // State changing functions
    function allocateEmissions() external returns (uint256 amount);
    function claimEmissions() external returns (uint256 amount);
    function setTreasuryAllocationPerEpoch(uint256 _treasuryAllocationPerEpoch) external;
    function sweepERC20(address token) external;
}
