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
    // Bound each isolated call so a gas-burning integration cannot consume the whole batch.
    uint256 public constant taskGasLimit = 2_000_000;
    // Preserve enough gas to record a failure and return without reverting earlier successful work.
    uint256 public constant taskGasReserve = 200_000;
    // View probes should be cheap; a failed or gas-burning probe is treated as unavailable.
    uint256 public constant checkGasLimit = 200_000;

    address public owner;
    address[] public operators;
    uint256 public minProfit;

    /// @notice Emitted when one best-effort maintenance action fails or is skipped for low gas.
    event TaskFailed(bytes4 indexed selector, address indexed target);

    error OnlySelf();

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
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
        if (!_executeTask(abi.encodeCall(this._workDistributeWeeklyFees, ()), address(registry), IFeeDepositController.distribute.selector)) return;
        if (!_executeTask(abi.encodeCall(this._workSyncSreUsdRewards, ()), address(sreUsd), ISreUsd.syncRewardsAndDistribution.selector)) return;

        address[] memory pairs;
        try registry.getAllPairAddresses() returns (address[] memory _pairs) {
            pairs = _pairs;
        } catch {
            emit TaskFailed(IResupplyRegistry.getAllPairAddresses.selector, address(registry));
        }
        for (uint256 i = 0; i < pairs.length; i++) {
            if (!_executeTask(abi.encodeCall(this._workWithdrawPairFees, (pairs[i])), pairs[i], IResupplyPair.withdrawFees.selector)) return;
            if (!_executeTask(abi.encodeCall(this._workUpdateBorrowLimit, (pairs[i])), pairs[i], IBorrowLimitController.updatePairBorrowLimit.selector)) return;
        }
        if (!_executeTask(abi.encodeCall(this._workClaimRetentionEmissions, ()), address(registry), IRetentionReceiver.claimEmissions.selector)) return;
        for (uint256 i = 0; i < operators.length; i++) {
            if (!_executeTask(abi.encodeCall(this._workWithdrawProfit, (operators[i])), operators[i], IOperator.withdraw_profit.selector)) return;
        }
        _updateSwapperApprovals();
    }

    function canWork() external view returns (bool) {
        if (_canCheck(abi.encodeCall(this.canDistributeWeeklyFees, ()))) return true;
        if (_canCheck(abi.encodeCall(this.canSyncSreUsdRewards, ()))) return true;
        if (_canCheck(abi.encodeCall(this.canClaimRetentionEmissions, ()))) return true;

        address[] memory pairs;
        try registry.getAllPairAddresses() returns (address[] memory _pairs) {
            pairs = _pairs;
        } catch { }
        for (uint256 i = 0; i < pairs.length; i++) {
            if (_canCheck(abi.encodeCall(this.canWithdrawFees, (pairs[i])))) return true;
            if (_canCheck(abi.encodeCall(this.canUpdateBorrowLimit, (pairs[i])))) return true;
        }
        for (uint256 i = 0; i < operators.length; i++) {
            if (_canCheck(abi.encodeCall(this.canWithdrawProfit, (operators[i])))) return true;
        }
        return _canCheck(abi.encodeCall(this.canUpdateSwapperApprovals, ()));
    }

    // External self-calls give each action its own revert boundary without exposing arbitrary targets.
    function _workDistributeWeeklyFees() external onlySelf {
        if (canDistributeWeeklyFees()) _getFeeDepositController().distribute();
    }

    function _workSyncSreUsdRewards() external onlySelf {
        if (canSyncSreUsdRewards()) sreUsd.syncRewardsAndDistribution();
    }

    function _workWithdrawPairFees(address _pair) external onlySelf {
        if (canWithdrawFees(_pair)) IResupplyPair(_pair).withdrawFees();
    }

    function _workUpdateBorrowLimit(address _pair) external onlySelf {
        IBorrowLimitController controller = _getBorrowLimitController();
        if (_canUpdateBorrowLimit(controller, _pair)) controller.updatePairBorrowLimit(_pair);
    }

    function _workClaimRetentionEmissions() external onlySelf {
        if (canClaimRetentionEmissions()) _getRetentionReceiver().claimEmissions();
    }

    function _workWithdrawProfit(address _operator) external onlySelf {
        if (canWithdrawProfit(_operator)) IOperator(_operator).withdraw_profit();
    }

    function _workUpdateSwapperApprovals(address _swapper) external onlySelf {
        if (IRouterSwapper(_swapper).canUpdateApprovals()) IRouterSwapper(_swapper).updateApprovals();
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

            if (!_executeTask(abi.encodeCall(this._workUpdateSwapperApprovals, (swapper)), swapper, IRouterSwapper.updateApprovals.selector)) return;
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
        if (preview <= current) return false;

        uint256 currentProgress = ((current - limit.prevBorrowLimit) * 10_000 + borrowDelta - 1) / borrowDelta;

        // Add one ramp basis point because the applied limit does not preserve the exact update timestamp.
        uint256 minimumProgress = (borrowLimitUpdateInterval * 10_000 + duration - 1) / duration + 1;
        return previewProgress >= currentProgress + minimumProgress;
    }

    function _executeTask(bytes memory _data, address _target, bytes4 _selector) internal returns (bool) {
        uint256 availableGas = gasleft();
        if (availableGas <= taskGasReserve) {
            emit TaskFailed(_selector, _target);
            return false;
        }

        uint256 forwardedGas = availableGas - taskGasReserve;
        if (forwardedGas > taskGasLimit) forwardedGas = taskGasLimit;

        address self = address(this);
        bool success;
        // Do not copy return data: a failing target cannot grief the outer batch with a large payload.
        assembly {
            success := call(forwardedGas, self, 0, add(_data, 32), mload(_data), 0, 0)
        }
        if (!success) emit TaskFailed(_selector, _target);
        return true;
    }

    function _canCheck(bytes memory _data) internal view returns (bool) {
        address self = address(this);
        uint256 gasLimit = checkGasLimit;
        uint256 result;
        bool success;
        // Copy at most one word so a reverting probe cannot force an unbounded allocation.
        assembly {
            let output := mload(0x40)
            success := staticcall(gasLimit, self, add(_data, 32), mload(_data), output, 32)
            if and(success, eq(returndatasize(), 32)) {
                result := mload(output)
            }
        }
        return success && result == 1;
    }

    function getEpoch() public view returns (uint256) {
        return (block.timestamp - startTime) / epochLength;
    }
}
