// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IUpgradeOperator {
    event UpgradeExecuted(address indexed target, address indexed implementation, bytes data);
    event ManagerSet(address indexed manager);

    function manager() external view returns (address);
    function setManager(address _manager) external;
    function upgradeToAndCall(address target, address newImplementation, bytes calldata data) external;
    function canUpgrade(address target) external view returns (bool);
}
