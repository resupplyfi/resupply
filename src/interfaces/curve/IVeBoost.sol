// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IVeBoost {
    function delegable_balance(address _addr) external view returns (uint256);
    function boost(address _to, uint256 _amount, uint256 _endtime, address _from) external;
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function adjusted_balance_of(address user) external view returns (uint256);
}
