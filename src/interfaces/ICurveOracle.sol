// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveOracle {

    function price() external view returns(uint256);
    function price_w() external returns(uint256);
    function price_oracle() external view returns(uint256);
}