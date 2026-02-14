// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveFeeDistributor {
    function claim(address recipient) external returns (uint256);
}