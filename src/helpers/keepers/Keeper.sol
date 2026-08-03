// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { IFeeDeposit } from "src/interfaces/IFeeDeposit.sol";
import { IRetentionReceiver } from "src/interfaces/IRetentionReceiver.sol";
import { IEmissionsController } from "src/interfaces/IEmissionsController.sol";
import { IRouterSwapper } from "src/interfaces/IRouterSwapper.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";

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
    uint256 public constant startTime = 1_741_824_000;
    uint256 public constant epochLength = 1 weeks;
    uint256 public constant borrowLimitUpdateInterval = 12 hours;

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
        _work();
    }

    /// @param _borrowLimitPairs Pairs prefiltered offchain with canUpdateBorrowLimit.
    function work(address[] calldata _borrowLimitPairs) external {
        _work();
        _updateBorrowLimits(_borrowLimitPairs);
    }

    function _work() internal {
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
        _updateSwapperApprovals();
    }

    function canWork() external view returns (bool) {
        return _canWork();
    }

    /// @param _borrowLimitPairs Pairs to check for borrow-limit upkeep.
    function canWork(address[] calldata _borrowLimitPairs) external view returns (bool) {
        if (_canWork()) return true;
        IBorrowLimitController controller = _getBorrowLimitController();
        for (uint256 i = 0; i < _borrowLimitPairs.length; i++) {
            if (_canUpdateBorrowLimit(controller, _borrowLimitPairs[i])) return true;
        }
        return false;
    }

    function _canWork() internal view returns (bool) {
        address[] memory pairs = registry.getAllPairAddresses();
        if (canDistributeWeeklyFees()) return true;
        if (canSyncSreUsdRewards()) return true;
        if (canClaimRetentionEmissions()) return true;
        for (uint256 i = 0; i < pairs.length; i++) {
            if (canWithdrawFees(pairs[i])) return true;
        }
        for (uint256 i = 0; i < operators.length; i++) {
            if (canWithdrawProfit(operators[i])) return true;
        }
        return canUpdateSwapperApprovals();
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

    function canUpdateSwapperApprovals() public view returns (bool) {
        for (uint256 i = 0;; i++) {
            try registry.defaultSwappers(i) returns (address swapper) {
                try IRouterSwapper(swapper).canUpdateApprovals() returns (bool _canUpdate) {
                    if (_canUpdate) return true;
                } catch { }
            } catch {
                break;
            }
        }
        return false;
    }

    function canUpdateBorrowLimit(address _pair) public view returns (bool) {
        return _canUpdateBorrowLimit(_getBorrowLimitController(), _pair);
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

    function _getBorrowLimitController() internal view returns (IBorrowLimitController) {
        return IBorrowLimitController(registry.getAddress("BORROW_LIMIT_CONTROLLER"));
    }

    function _updateSwapperApprovals() internal {
        for (uint256 i = 0;; i++) {
            address swapper;
            try registry.defaultSwappers(i) returns (address _swapper) {
                swapper = _swapper;
            } catch {
                return;
            }

            bool canUpdate;
            try IRouterSwapper(swapper).canUpdateApprovals() returns (bool _canUpdate) {
                canUpdate = _canUpdate;
            } catch {
                continue;
            }

            if (canUpdate) IRouterSwapper(swapper).updateApprovals();
        }
    }

    function _updateBorrowLimits(address[] calldata _pairs) internal {
        IBorrowLimitController controller = _getBorrowLimitController();
        for (uint256 i = 0; i < _pairs.length; i++) {
            if (_canUpdateBorrowLimit(controller, _pairs[i])) controller.updatePairBorrowLimit(_pairs[i]);
        }
    }

    function _canUpdateBorrowLimit(IBorrowLimitController _controller, address _pair) internal view returns (bool) {
        IBorrowLimitController.PairBorrowLimit memory limit = _controller.pairLimits(_pair);
        if (limit.startTime == 0) return false;

        uint256 current = IResupplyPair(_pair).borrowLimit();
        if (current == 0 || current < limit.prevBorrowLimit || current > limit.targetBorrowLimit) return false;
        if (block.timestamp >= limit.endTime) return true;

        uint256 borrowDelta = limit.targetBorrowLimit - limit.prevBorrowLimit;
        uint256 duration = limit.endTime - limit.startTime;
        uint256 previewProgress = (block.timestamp - limit.startTime) * 10_000 / duration;
        uint256 preview = (borrowDelta * previewProgress) / 10_000 + limit.prevBorrowLimit;
        if (preview <= current) return false;

        uint256 currentProgress = ((current - limit.prevBorrowLimit) * 10_000 + borrowDelta - 1) / borrowDelta;

        // Add one ramp basis point because the applied limit does not preserve the exact update timestamp.
        uint256 minimumProgress = (borrowLimitUpdateInterval * 10_000 + duration - 1) / duration + 1;
        return previewProgress >= currentProgress + minimumProgress;
    }

    function getEpoch() public view returns (uint256) {
        return (block.timestamp - startTime) / epochLength;
    }
}
