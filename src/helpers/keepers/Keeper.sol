// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { IFeeDeposit } from "src/interfaces/IFeeDeposit.sol";
import { IRetentionReceiver } from "src/interfaces/IRetentionReceiver.sol";
import { IEmissionsController } from "src/interfaces/IEmissionsController.sol";

interface IOperator {
    function profit() external view returns (uint256);
    function withdraw_profit() external;
}

interface ISreUsd {
    function lastRewardsDistribution() external view returns (uint256);
    function syncRewardsAndDistribution() external;
}

contract Keeper {
    IResupplyRegistry public constant registry = IResupplyRegistry(0x10101010E0C3171D894B71B3400668aF311e7D94);
    ISreUsd public constant sreUsd = ISreUsd(0x557AB1e003951A73c12D16F0fEA8490E39C33C35);
    uint256 public constant startTime = 1741824000;
    uint256 public constant epochLength = 1 weeks;

    address public owner;
    address[] public operators;
    uint256 public minProfit;

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    constructor(address _owner, address[] memory _operators, uint256 _minProfit) {
        owner = _owner;
        operators = _operators;
        minProfit = _minProfit;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function setOperators(address[] calldata _operators, uint256 _minProfit) external onlyOwner {
        operators = _operators;
        minProfit = _minProfit;
    }

    function getOperators() external view returns (address[] memory) {
        return operators;
    }

    function work() external {
        if (canDistributeWeeklyFees()) _getFeeDepositController().distribute();
        if (canSyncSreUsdRewards()) sreUsd.syncRewardsAndDistribution();
        address[] memory pairs = registry.getAllPairAddresses();
        for (uint256 i = 0; i < pairs.length; i++) {
            if (canWithdrawFees(pairs[i])) IResupplyPair(pairs[i]).withdrawFees();
        }
        if (canClaimRetentionEmissions()) _getRetentionReceiver().claimEmissions();
        for (uint256 i = 0; i < operators.length; i++) {
            if (canWithdrawProfit(operators[i])) IOperator(operators[i]).withdraw_profit();
        }
    }

    function canWork() external view returns (bool) {
        address[] memory pairs = registry.getAllPairAddresses();
        if (canDistributeWeeklyFees()) return true;
        if (canSyncSreUsdRewards()) return true;
        if (canClaimRetentionEmissions()) return true;
        for (uint256 i = 0; i < pairs.length; i++) 
            if (canWithdrawFees(pairs[i])) return true;
        return false;
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

    function canWithdrawProfit(address _operator) public view returns (bool) {
        return IOperator(_operator).profit() > minProfit;
    }

    function canSyncSreUsdRewards() public view returns (bool) {
        uint256 lastRewardsDistribution = sreUsd.lastRewardsDistribution();
        return ((lastRewardsDistribution - startTime) / epochLength) < getEpoch();
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

    function getEpoch() public view returns (uint256) {
        return (block.timestamp - startTime) / epochLength;
    }
}
