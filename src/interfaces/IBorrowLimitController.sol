// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IBorrowLimitController {
    struct PairBorrowLimit {
        uint256 targetBorrowLimit;
        uint256 prevBorrowLimit;
        uint64 startTime;
        uint64 endTime;
    }

    function cancelRamp(address _pair) external;

    function setPairBorrowLimitRamp(address _pair, uint256 _newBorrowLimit, uint256 _endTime) external;

    function updatePairBorrowLimit(address _pair) external;

    function previewNewBorrowLimit(address _pair) external view returns (uint256);

    // View function for public state variable
    function pairLimits(address _pair) external view returns (PairBorrowLimit memory);
}
