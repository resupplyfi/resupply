// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IReceiver {
    /**
     * @notice Fetches emissions for the receiver
     * @return The amount of emissions fetched
     */
    function allocateEmissions() external returns (uint256);
    function getReceiverId() external view returns (uint256);
}
