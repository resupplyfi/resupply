// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRedemptionOperator {
    function setApprovedCaller(address _caller, bool _status) external;
}
