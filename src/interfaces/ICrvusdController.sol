// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICrvusdController{
    function set_debt_ceiling(address _to, uint256 _debt_ceiling) external;
    function rug_debt_ceiling(address _to) external;
    function fee_receiver() external view returns(address);
}