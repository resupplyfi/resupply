// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRateCalculatorV2Old {
    function name() external view returns (string memory);

    function version() external view returns (uint256, uint256, uint256);

    function getNewRate(
        uint256 _deltaTime,
        uint256 _utilization,
        uint64 _maxInterest
    ) external view returns (uint64 _newRatePerSec, uint64 _newMaxInterest);
}
