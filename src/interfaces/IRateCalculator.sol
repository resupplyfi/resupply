// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

interface IRateCalculator {
    function name() external view returns (string memory);

    function version() external view returns (uint256, uint256, uint256);

    function getNewRate(
        address _vault,
        uint256 _deltaTime,
        uint256 _previousShares,
        uint256 _previousPrice
    ) external view returns (uint64 _newRatePerSec, uint256 _newPrice, uint256 _newShares);
}
