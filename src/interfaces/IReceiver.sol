// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IReceiver {
    /**
     * @notice Fetches emissions for the receiver
     * @return The amount of emissions fetched
     */
    function fetchAllocatedEmissions() external returns (uint256);
}
