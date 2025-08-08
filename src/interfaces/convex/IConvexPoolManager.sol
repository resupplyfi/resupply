// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IConvexPoolManager {
    function addPool(address _pool) external returns (bool);
}