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

    address public owner;
    address[] public operators;
    uint256 public minProfit;
    /// @notice Minimum time between successful Keeper borrow limit updates.
    uint64 public borrowLimitUpdateInterval = 12 hours;
    /// @notice Timestamp of the last successful Keeper borrow limit update.
    uint64 public lastBorrowLimitUpdate;

    /// @notice Emitted after a maintenance action completes successfully.
    event TaskCompleted(bytes4 indexed selector, address indexed subject);
    /// @notice Emitted when a best-effort maintenance action fails.
    event TaskFailed(bytes4 indexed selector, address indexed subject);
    /// @notice Emitted when the minimum interval between borrow limit updates changes.
    event BorrowLimitUpdateIntervalSet(uint64 interval);

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

    /// @dev Setting the interval to zero disables the cooldown.
    function setBorrowLimitUpdateInterval(uint64 _interval) external onlyOwner {
        borrowLimitUpdateInterval = _interval;
        emit BorrowLimitUpdateIntervalSet(_interval);
    }

    function getOperators() external view returns (address[] memory) {
        return operators;
    }

    function work() external {
        bool weeklyWork = canDistributeWeeklyFees();
        if (weeklyWork) {
            IFeeDepositController controller = _getFeeDepositController();
            controller.distribute();
            emit TaskCompleted(IFeeDepositController.distribute.selector, address(controller));
        }

        if (canSyncSreUsdRewards()) {
            sreUsd.syncRewardsAndDistribution();
            emit TaskCompleted(ISreUsd.syncRewardsAndDistribution.selector, address(sreUsd));
        }

        address[] memory pairs = registry.getAllPairAddresses();
        bool checkBorrowLimits = _borrowLimitUpdateIntervalElapsed();
        IBorrowLimitController borrowLimitController;
        if (checkBorrowLimits) borrowLimitController = _getBorrowLimitController();
        bool borrowLimitUpdated;
        for (uint256 i = 0; i < pairs.length; i++) {
            if (canWithdrawFees(pairs[i])) {
                IResupplyPair(pairs[i]).withdrawFees();
                emit TaskCompleted(IResupplyPair.withdrawFees.selector, pairs[i]);
            }
            if (checkBorrowLimits && _canUpdateBorrowLimit(borrowLimitController, pairs[i])) {
                borrowLimitController.updatePairBorrowLimit(pairs[i]);
                borrowLimitUpdated = true;
                emit TaskCompleted(IBorrowLimitController.updatePairBorrowLimit.selector, pairs[i]);
            }
        }
        if (borrowLimitUpdated) lastBorrowLimitUpdate = uint64(block.timestamp);

        if (canClaimRetentionEmissions()) {
            IRetentionReceiver retention = _getRetentionReceiver();
            retention.claimEmissions();
            emit TaskCompleted(IRetentionReceiver.claimEmissions.selector, address(retention));
        }

        if (weeklyWork) {
            for (uint256 i = 0; i < operators.length; i++) {
                if (canWithdrawProfit(operators[i])) {
                    IOperator(operators[i]).withdraw_profit();
                    emit TaskCompleted(IOperator.withdraw_profit.selector, operators[i]);
                }
            }
        }

        _updateSwapperApprovals();
    }

    function canWork() external view returns (bool) {
        if (canDistributeWeeklyFees()) return true;
        if (canSyncSreUsdRewards()) return true;
        if (canClaimRetentionEmissions()) return true;
        address[] memory pairs = registry.getAllPairAddresses();
        bool checkBorrowLimits = _borrowLimitUpdateIntervalElapsed();
        IBorrowLimitController borrowLimitController;
        if (checkBorrowLimits) borrowLimitController = _getBorrowLimitController();
        for (uint256 i = 0; i < pairs.length; i++) {
            if (canWithdrawFees(pairs[i])) return true;
            if (checkBorrowLimits && _canUpdateBorrowLimit(borrowLimitController, pairs[i])) return true;
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
        if (!_borrowLimitUpdateIntervalElapsed()) return false;
        return _canUpdateBorrowLimit(_getBorrowLimitController(), _pair);
    }

    function canSyncSreUsdRewards() public view returns (bool) {
        uint256 lastRewardsDistribution = sreUsd.lastRewardsDistribution();
        if (lastRewardsDistribution < startTime) return false;
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

            if (!canUpdate) continue;

            try IRouterSwapper(swapper).updateApprovals() {
                emit TaskCompleted(IRouterSwapper.updateApprovals.selector, swapper);
            } catch {
                emit TaskFailed(IRouterSwapper.updateApprovals.selector, swapper);
            }
        }
    }

    function _canUpdateBorrowLimit(IBorrowLimitController _controller, address _pair) internal view returns (bool) {
        IBorrowLimitController.PairBorrowLimit memory limit = _controller.pairLimits(_pair);
        if (limit.startTime == 0 || block.timestamp < limit.startTime || limit.endTime <= limit.startTime || limit.targetBorrowLimit <= limit.prevBorrowLimit) return false;

        uint256 current = IResupplyPair(_pair).borrowLimit();
        if (current == 0 || current < limit.prevBorrowLimit || current > limit.targetBorrowLimit) return false;
        if (block.timestamp >= limit.endTime) return true;

        uint256 borrowDelta = limit.targetBorrowLimit - limit.prevBorrowLimit;
        uint256 duration = limit.endTime - limit.startTime;
        uint256 previewProgress = (block.timestamp - limit.startTime) * 10_000 / duration;
        uint256 preview = (borrowDelta * previewProgress) / 10_000 + limit.prevBorrowLimit;
        return preview > current;
    }

    function _borrowLimitUpdateIntervalElapsed() internal view returns (bool) {
        return block.timestamp - lastBorrowLimitUpdate >= borrowLimitUpdateInterval;
    }

    function getEpoch() public view returns (uint256) {
        return (block.timestamp - startTime) / epochLength;
    }
}
