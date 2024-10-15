// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/ICore.sol";

/**
    @title Prisma System Start Time
    @dev Provides a unified `startTime` and `getWeek`, used for emissions.
 */
contract SystemStart {
    uint256 immutable startTime;
    uint256 immutable epochLength;

    constructor(address _core) {
        startTime = ICore(_core).startTime();
        epochLength = ICore(_core).epochLength();
    }

    function getEpoch() public view returns (uint256 epoch) {
        return (block.timestamp - startTime) / epochLength;
    }
}