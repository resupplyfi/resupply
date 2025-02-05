// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IMinter {
    function mint(address _to, uint256 _amount) external;
}