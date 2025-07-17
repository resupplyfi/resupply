// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface IPrismaFeeReceiver {
    function PRISMA_CORE() external view returns (address);

    function guardian() external view returns (address);

    function owner() external view returns (address);

    function setTokenApproval(
        address token,
        address spender,
        uint256 amount
    ) external;

    function transferToken(
        address token,
        address receiver,
        uint256 amount
    ) external;
}