// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/ICore.sol";

/**
    @title EpochTracker
    @dev Provides a unified `startTime` and `getEpoch`, used for tracking epochs.
 */
contract EpochTracker {
    uint256 public immutable startTime;
    
    /// @notice Length of an epoch, in seconds
    uint256 public immutable epochLength;

    constructor(address _core) {
        startTime = ICore(_core).startTime();
        epochLength = ICore(_core).epochLength();
    }

    function getEpoch() public view returns (uint256 epoch) {
        return (block.timestamp - startTime) / epochLength;
    }
}