// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IUpgradeableOperator {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external;
    function proxiableUUID() external view returns (bytes32);
    function UPGRADE_INTERFACE_VERSION() external view returns (string memory);
}
