// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IReusdOracle {
    function price() external view returns (uint256 _price);
    function priceAsCrvusd() external view returns (uint256 _price);
    function priceAsFrxusd() external view returns (uint256 _price);
    function oraclePriceAsCrvusd() external view returns (uint256 _price);
    function oraclePriceAsFrxusd() external view returns (uint256 _price);
    function spotPriceAsCrvusd() external view returns (uint256 _price);
    function spotPriceAsFrxusd() external view returns (uint256 _price);
}
