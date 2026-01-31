// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IUpgradeableOperator {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external;
}
