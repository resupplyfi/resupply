// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IPriceWatcher {
    struct PriceData{
        uint64 timestamp;
        uint64 weight;
        uint128 totalWeight;
    }
    event NewPriceData(uint256 indexed index, uint64 timestamp, uint64 weight, uint128 weightedValue);
    event OracleSet(address indexed oracle);

    function UPDATE_INTERVAL() external view returns(uint256);
    function registry() external view returns(address);
    function oracle() external view returns(address);
    function updatePriceData() external;
    function priceDataLength() external view returns(uint256);
    function priceDataAtIndex(uint256 i) external view returns(PriceData memory _pd);
    function latestPriceData() external view returns(PriceData memory _pd);
    function findPairPriceWeight(address _pair) external view returns(uint256);
    function getCurrentWeight() external view returns(uint64);
    function canUpdatePriceData() external view returns(bool);
    function setOracle() external;
}
