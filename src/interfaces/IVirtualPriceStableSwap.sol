// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IVirtualPriceStableSwap {
    function get_virtual_price() external view returns (uint256);
}
