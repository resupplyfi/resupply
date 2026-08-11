// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFrxUsd {
    function isPaused() external view returns (bool);
    function minters(address account) external view returns (bool);
}
