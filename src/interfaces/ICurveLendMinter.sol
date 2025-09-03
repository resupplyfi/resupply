// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveLendMinter{
    function initialize(address _owner, address _factory, address _market) external;
    function setMintLimit(uint256 _newLimit) external;
    function reduceAmount(uint256 _amount) external;
}