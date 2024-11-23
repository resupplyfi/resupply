// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

interface IRateCalculator {
    function name() external view returns (string memory);

    function version() external view returns (uint256, uint256, uint256);

    function getNewRate(
        address _vault,
        uint256 _deltaTime,
        uint256 _previousShares
    ) external view returns (uint64 _newRatePerSec, uint128 _newShares);
}
