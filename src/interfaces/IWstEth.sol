// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IWstEth {
    function getStETHByWstETH(uint256) external view returns (uint256);
}
