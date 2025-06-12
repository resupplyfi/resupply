// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPriceWatcher {
    struct PriceData{
        uint64 timestamp;
        uint64 weight;
        uint128 totalWeight;
    }

    function updatePriceData() external;
    function updatePairPriceHistory(address _pair) external;
    function priceDataLength() external view returns(uint256);
    function priceDataAtIndex(uint256 i) external view returns(PriceData memory _pd);
    function latestPriceData() external view returns(PriceData memory _pd);
    function findPairPriceWeight(address _pair) external view returns(uint256);
    function updatePairPriceHistoryAtIndex(address _pair, uint256 _index) external;
}
