// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { IFeeDeposit } from "src/interfaces/IFeeDeposit.sol";
import { IRetentionReceiver } from "src/interfaces/IRetentionReceiver.sol";
import { IEmissionsController } from "src/interfaces/IEmissionsController.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @custom:oz-upgrades-from Keeper
contract KeeperV2 is UUPSUpgradeable {
    IResupplyRegistry public constant registry = IResupplyRegistry(0x10101010E0C3171D894B71B3400668aF311e7D94);
    uint256 public constant startTime = 1741824000;
    uint256 public constant epochLength = 1 weeks;
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function work() external {
        if (canDistributeWeeklyFees()) _getFeeDepositController().distribute();
        address[] memory pairs = registry.getAllPairAddresses();
        for (uint256 i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            if (canWithdrawFees(pair)) IResupplyPair(pair).withdrawFees();
        }
        if (canClaimRetentionEmissions()) _getRetentionReceiver().claimEmissions();
    }

    function initialize() external initializer {}

    function canWork() external view returns (bool) {
        return canDistributeWeeklyFees();
    }

    function canDistributeWeeklyFees() public view returns (bool) {
        return _getFeeDeposit().lastDistributedEpoch() < getEpoch();
    }
    
    function canWithdrawFees(address _pair) public view returns (bool) {
        if (IResupplyPair(_pair).lastFeeEpoch() >= getEpoch()) return false;
        (address oracle,,) = IResupplyPair(_pair).exchangeRateInfo();
        if (oracle == address(0)) return false;
        return true;
    }

    function canClaimRetentionEmissions() public view returns (bool) {
        IRetentionReceiver retention = _getRetentionReceiver();
        if (!_getEmissionsController().isRegisteredReceiver(address(retention))) return false;
        return getEpoch() > retention.lastEpoch();
    }

    function _getFeeDepositController() internal view returns (IFeeDepositController) {
        return IFeeDepositController(registry.getAddress("FEE_DEPOSIT_CONTROLLER"));
    }

    function _getFeeDeposit() internal view returns (IFeeDeposit) {
        return IFeeDeposit(registry.feeDeposit());
    }

    function _getRetentionReceiver() internal view returns (IRetentionReceiver) {
        return IRetentionReceiver(registry.getAddress("RETENTION_RECEIVER"));
    }

    function _getEmissionsController() internal view returns (IEmissionsController) {
        return IEmissionsController(registry.getAddress("EMISSIONS_CONTROLLER"));
    }

    function getEpoch() public view returns (uint256 epoch) {
        return (block.timestamp - startTime) / epochLength;
    }
}