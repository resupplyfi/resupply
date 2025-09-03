// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveLendMinterFactory{
    function fee_receiver() external view returns(address);
    function pull_funds(address _market, uint256 _amount) external;
}