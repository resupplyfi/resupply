// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { IUpgradeableOperator } from "src/interfaces/IUpgradeableOperator.sol";

/**
 * @title UpgradeOperator
 * @notice Allows a manager to upgrade proxies that have been delegated by governance.
 */
contract UpgradeOperator is CoreOwnable {
    address public manager;

    event UpgradeExecuted(address indexed target, address indexed implementation, bytes data);
    event ManagerSet(address indexed manager);

    modifier onlyOwnerOrManager() {
        require(msg.sender == manager || msg.sender == owner(), "!authorized");
        _;
    }

    constructor(address _core, address _manager) CoreOwnable(_core) {
        require(_manager != address(0), "invalid manager");
        manager = _manager;
        emit ManagerSet(_manager);
    }

    function setManager(address _manager) external onlyOwner {
        require(_manager != address(0), "invalid manager");
        manager = _manager;
        emit ManagerSet(_manager);
    }

    function upgradeToAndCall(address target, address newImplementation, bytes calldata data) external onlyOwnerOrManager {
        core.execute(
            target,
            abi.encodeWithSelector(IUpgradeableOperator.upgradeToAndCall.selector, newImplementation, data)
        );
        emit UpgradeExecuted(target, newImplementation, data);
    }
}
