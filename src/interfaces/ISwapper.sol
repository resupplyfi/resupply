// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISwapper {
    function swap(
        address account,
        uint256 amountIn,
        address[] calldata path,
        address to
    ) external;

    function swapPools(address tokenIn, address tokenOut) external view returns(address swappool, int32 tokenInIndex, int32 tokenOutIndex, uint32 swaptype);
}
