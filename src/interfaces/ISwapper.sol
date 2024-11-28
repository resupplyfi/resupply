// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

interface ISwapper {
    function swap(
        address account,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external returns (uint256 amountOut);
}
