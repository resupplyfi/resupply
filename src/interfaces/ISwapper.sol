// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

interface ISwapper {
    function swap(
        address account,
        uint256 amountIn,
        address[] calldata path,
        address to
    ) external;
}
