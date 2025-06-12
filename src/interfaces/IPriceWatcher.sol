// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPriceWatcher {
    function updatePriceData() external;
    function updatePairPriceHistory(address _pair) external;
}
