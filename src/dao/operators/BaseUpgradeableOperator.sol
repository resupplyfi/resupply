// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title BaseUpgradeableOperator
 * @notice Base contract for all upgradeable operator proxies.
 * @dev This contract is used to manage the upgradeability of the operator proxies.
 * @dev The core address is the owner of the contract.
 */
abstract contract BaseUpgradeableOperator is UUPSUpgradeable {
    address public constant CORE = 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d;

    modifier onlyOwner() {
        require(msg.sender == CORE, "!owner");
        _;
    }

    function owner() external view returns (address) {
        return CORE;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}