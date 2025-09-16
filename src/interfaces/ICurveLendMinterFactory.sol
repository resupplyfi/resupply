// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveLendMinterFactory{
    function owner() external view returns(address);
    function admin() external view returns(address);
    function fee_receiver() external view returns(address);
    function borrow(address _market, uint256 _amount) external;
    function addMarketOperator(address _market, uint256 _initialMintLimit) external returns(address);
}