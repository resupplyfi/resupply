// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveLend {

    function lend_apr() external view returns(uint256);
}