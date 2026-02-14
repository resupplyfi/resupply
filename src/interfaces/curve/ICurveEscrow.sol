// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveEscrow {
    function create_lock(uint256 value, uint256 unlock_time) external;
    function balanceOf(address _addr) external view returns (uint256);
    function increase_unlock_time(uint256 _unlock_time) external;
    function locked__end(address _addr) external returns (uint256);
}