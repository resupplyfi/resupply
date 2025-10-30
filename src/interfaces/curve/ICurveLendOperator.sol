// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveLendOperator{
    function withdraw_profit() external;
    function profit() external view returns(uint256);
    function mintLimit() external view returns(uint256);
    function mintedAmount() external view returns(uint256);
    function initialize(address _factory, address _market, uint256 _initialMintLimit) external;
    function setMintLimit(uint256 _newLimit) external;
    function reduceAmount(uint256 _amount) external;
    function factory() external view returns(address);
}