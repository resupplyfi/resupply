// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { Keeper, IOperator } from "src/helpers/keepers/Keeper.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRouterSwapper } from "src/interfaces/IRouterSwapper.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IFeeDeposit } from "src/interfaces/IFeeDeposit.sol";
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { Protocol } from "src/Constants.sol";

contract RevertingApprovalUpdater {
    error UpdateFailed();

    function canUpdateApprovals() external pure returns (bool) {
        return true;
    }

    function updateApprovals() external pure {
        revert UpdateFailed();
    }
}

contract NonApprovalUpdater { }

contract RevertingProfitOperator {
    error ProbeFailed();

    function profit() external pure returns (uint256) {
        revert ProbeFailed();
    }

    function withdraw_profit() external pure { }
}

contract ProfitOperator {
    uint256 public profit;
    uint256 public withdrawals;

    constructor(uint256 _profit) {
        profit = _profit;
    }

    function withdraw_profit() external {
        profit = 0;
        withdrawals++;
    }
}

contract KeeperOperationsTest is Test {
    uint256 internal constant FORK_BLOCK = 25_674_238;
    uint256 internal constant MIN_PROFIT = 100e18;
    bytes32 internal constant TASK_COMPLETED_TOPIC = keccak256("TaskCompleted(bytes4,address)");
    bytes32 internal constant TASK_FAILED_TOPIC = keccak256("TaskFailed(bytes4,address)");

    IResupplyRegistry internal constant registry = IResupplyRegistry(Protocol.REGISTRY);
    IRouterSwapper internal constant lifi = IRouterSwapper(0x597Db76794c75E588D3a70534FB34B7780941fCe);
    IRouterSwapper internal constant enso = IRouterSwapper(0x181c98113ce60BA75A0f72d8901Eb17e5065043D);
    IBorrowLimitController internal constant borrowLimitController = IBorrowLimitController(Protocol.BORROW_LIMIT_CONTROLLER);
    IResupplyPair internal constant sdolaPair = IResupplyPair(0xEcceF525b3063705DA5075a1ce5De1892D24C25A);
    IResupplyPair internal constant sfrxUsdPair = IResupplyPair(0x0837E20D15585B4cA5c1a3fCedCCF8f72855Cb56);
    IResupplyPair internal constant pausedFxSavePair = IResupplyPair(0xD42535Cda82a4569BA7209857446222ABd14A82c);

    Keeper internal keeper;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"), FORK_BLOCK);
        keeper = new Keeper(address(this), new address[](0), MIN_PROFIT);
    }

    function test_CanWorkWhenSwapperApprovalsNeedUpdate() public {
        _disableBorrowLimitUpdates();

        assertTrue(keeper.canUpdateSwapperApprovals());
        assertTrue(keeper.canWork());
    }

    function test_CanWorkWhenBorrowLimitCanUpdate() public {
        _disableSwapperUpdates();

        assertTrue(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertTrue(keeper.canWork());
    }

    function test_WorkUpdatesSwapperApprovals() public {
        assertEq(lifi.nextPairIndex(), 19);
        assertEq(enso.nextPairIndex(), 19);

        vm.recordLogs();
        keeper.work();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(lifi.nextPairIndex(), 21);
        assertEq(enso.nextPairIndex(), 21);
        assertFalse(keeper.canUpdateSwapperApprovals());
        assertFalse(keeper.canWork());
        assertTrue(_hasTaskEvent(logs, TASK_COMPLETED_TOPIC, IRouterSwapper.updateApprovals.selector, address(lifi)));
        assertTrue(_hasTaskEvent(logs, TASK_COMPLETED_TOPIC, IRouterSwapper.updateApprovals.selector, address(enso)));
    }

    function test_WorkIsPermissionlessAndRepeatableAfterFrontRun() public {
        vm.prank(address(0xBEEF));
        keeper.work();

        assertEq(lifi.nextPairIndex(), 21);
        assertEq(enso.nextPairIndex(), 21);
        assertFalse(keeper.canWork());

        // The team's later transaction remains a successful no-op based on downstream state.
        keeper.work();
        assertFalse(keeper.canWork());
    }

    function test_OperatorProfitDoesNotTriggerOrRunNonWeeklyWork() public {
        _disableSwapperUpdates();
        _disableBorrowLimitUpdates();
        ProfitOperator profitOperator = new ProfitOperator(MIN_PROFIT + 1);

        address[] memory operators = new address[](1);
        operators[0] = address(profitOperator);
        keeper.setOperators(operators, MIN_PROFIT);

        assertTrue(keeper.canWithdrawProfit(address(profitOperator)));
        assertFalse(keeper.canWork());

        keeper.work();

        assertEq(profitOperator.withdrawals(), 0);
        assertEq(profitOperator.profit(), MIN_PROFIT + 1);
    }

    function test_WeeklyWorkWithdrawsOperatorProfit() public {
        _disableSwapperUpdates();
        _disableBorrowLimitUpdates();
        _enableWeeklyFeeDistribution();
        ProfitOperator profitOperator = new ProfitOperator(MIN_PROFIT + 1);

        address[] memory operators = new address[](1);
        operators[0] = address(profitOperator);
        keeper.setOperators(operators, MIN_PROFIT);

        assertTrue(keeper.canWork());

        vm.recordLogs();
        keeper.work();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(profitOperator.withdrawals(), 1);
        assertEq(profitOperator.profit(), 0);
        assertTrue(_hasTaskEvent(logs, TASK_COMPLETED_TOPIC, IOperator.withdraw_profit.selector, address(profitOperator)));
    }

    function test_SkipsSwappersWithoutUpdaterInterface() public {
        NonApprovalUpdater nonUpdater = new NonApprovalUpdater();
        _setOnlyDefaultSwapper(address(nonUpdater));
        _disableBorrowLimitUpdates();

        assertFalse(keeper.canUpdateSwapperApprovals());
        assertFalse(keeper.canWork());
        keeper.work();
    }

    function test_UpdateApprovalFailureDoesNotRollbackOtherWork() public {
        RevertingApprovalUpdater revertingUpdater = new RevertingApprovalUpdater();
        _setOnlyDefaultSwapper(address(revertingUpdater));
        uint256 sdolaPreview = borrowLimitController.previewNewBorrowLimit(address(sdolaPair));

        vm.recordLogs();
        keeper.work();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(sdolaPair.borrowLimit(), sdolaPreview);
        assertTrue(_hasTaskEvent(logs, TASK_COMPLETED_TOPIC, IBorrowLimitController.updatePairBorrowLimit.selector, address(sdolaPair)));
        assertTrue(_hasTaskEvent(logs, TASK_FAILED_TOPIC, IRouterSwapper.updateApprovals.selector, address(revertingUpdater)));
    }

    function test_WorkUpdatesBorrowLimits() public {
        uint256 sdolaPreview = borrowLimitController.previewNewBorrowLimit(address(sdolaPair));
        uint256 sfrxUsdPreview = borrowLimitController.previewNewBorrowLimit(address(sfrxUsdPair));

        assertTrue(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertTrue(keeper.canUpdateBorrowLimit(address(sfrxUsdPair)));

        vm.recordLogs();
        keeper.work();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(sdolaPair.borrowLimit(), sdolaPreview);
        assertEq(sfrxUsdPair.borrowLimit(), sfrxUsdPreview);
        assertEq(keeper.lastBorrowLimitUpdate(), block.timestamp);
        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertFalse(keeper.canUpdateBorrowLimit(address(sfrxUsdPair)));
        assertTrue(_hasTaskEvent(logs, TASK_COMPLETED_TOPIC, IBorrowLimitController.updatePairBorrowLimit.selector, address(sdolaPair)));
        assertTrue(_hasTaskEvent(logs, TASK_COMPLETED_TOPIC, IBorrowLimitController.updatePairBorrowLimit.selector, address(sfrxUsdPair)));
    }

    function test_BorrowLimitUpdatesAreRateLimited() public {
        keeper.work();
        uint256 lastUpdate = keeper.lastBorrowLimitUpdate();

        skip(12 hours - 1);
        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertFalse(keeper.canUpdateBorrowLimit(address(sfrxUsdPair)));
        assertFalse(keeper.canWork());

        skip(1);
        assertTrue(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertTrue(keeper.canUpdateBorrowLimit(address(sfrxUsdPair)));
        assertTrue(keeper.canWork());

        keeper.work();
        assertEq(keeper.lastBorrowLimitUpdate(), lastUpdate + 12 hours);
    }

    function test_BorrowLimitCooldownSkipsAllRampReads() public {
        keeper.work();
        uint256 lastUpdate = keeper.lastBorrowLimitUpdate();

        vm.mockCallRevert(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAddress.selector, "BORROW_LIMIT_CONTROLLER"), "borrow limit controller should not be read");
        vm.mockCallRevert(address(borrowLimitController), IBorrowLimitController.pairLimits.selector, "borrow limit ramps should not be read");

        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertFalse(keeper.canWork());
        keeper.work();
        assertEq(keeper.lastBorrowLimitUpdate(), lastUpdate);
    }

    function test_WorkWithoutBorrowLimitUpdateDoesNotStartCooldown() public {
        _disableBorrowLimitUpdates();

        keeper.work();

        assertEq(keeper.lastBorrowLimitUpdate(), 0);
    }

    function test_OwnerCanConfigureBorrowLimitUpdateInterval() public {
        assertEq(keeper.borrowLimitUpdateInterval(), 12 hours);
        keeper.work();

        skip(6 hours);
        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));

        keeper.setBorrowLimitUpdateInterval(6 hours);

        assertEq(keeper.borrowLimitUpdateInterval(), 6 hours);
        assertTrue(keeper.canUpdateBorrowLimit(address(sdolaPair)));
    }

    function test_NonOwnerCannotConfigureBorrowLimitUpdateInterval() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("!owner");
        keeper.setBorrowLimitUpdateInterval(6 hours);
    }

    function test_SkipsPausedBorrowLimitRamp() public view {
        IBorrowLimitController.PairBorrowLimit memory limit = borrowLimitController.pairLimits(address(pausedFxSavePair));

        assertGt(limit.startTime, 0);
        assertEq(pausedFxSavePair.borrowLimit(), 0);
        assertFalse(keeper.canUpdateBorrowLimit(address(pausedFxSavePair)));
    }

    function test_ExternalBorrowLimitUpdateDoesNotStartKeeperCooldown() public {
        borrowLimitController.updatePairBorrowLimit(address(sdolaPair));

        assertEq(keeper.lastBorrowLimitUpdate(), 0);
        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));
    }

    function test_CompletesBorrowLimitRamp() public {
        IBorrowLimitController.PairBorrowLimit memory limit = borrowLimitController.pairLimits(address(sdolaPair));
        vm.warp(limit.endTime);

        assertTrue(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        keeper.work();

        limit = borrowLimitController.pairLimits(address(sdolaPair));
        assertEq(sdolaPair.borrowLimit(), limit.targetBorrowLimit);
        assertEq(limit.startTime, 0);
    }

    function test_BorrowLimitUpdateFailureRevertsWork() public {
        uint256 sdolaBorrowLimit = sdolaPair.borrowLimit();
        uint256 sfrxUsdBorrowLimit = sfrxUsdPair.borrowLimit();
        vm.mockCallRevert(address(borrowLimitController), abi.encodeWithSelector(IBorrowLimitController.updatePairBorrowLimit.selector, address(sdolaPair)), "update failed");

        vm.expectRevert("update failed");
        keeper.work();

        assertEq(sdolaPair.borrowLimit(), sdolaBorrowLimit);
        assertEq(sfrxUsdPair.borrowLimit(), sfrxUsdBorrowLimit);
        assertEq(lifi.nextPairIndex(), 19);
        assertEq(enso.nextPairIndex(), 19);
    }

    function test_NonWeeklyWorkDoesNotProbeOperators() public {
        _disableSwapperUpdates();
        _disableBorrowLimitUpdates();
        assertFalse(keeper.canWork());

        address[] memory operators = new address[](1);
        operators[0] = address(new RevertingProfitOperator());
        keeper.setOperators(operators, MIN_PROFIT);

        assertFalse(keeper.canWork());
        keeper.work();
    }

    function _disableSwapperUpdates() internal {
        vm.mockCall(address(lifi), IRouterSwapper.canUpdateApprovals.selector, abi.encode(false));
        vm.mockCall(address(enso), IRouterSwapper.canUpdateApprovals.selector, abi.encode(false));
    }

    function _disableBorrowLimitUpdates() internal {
        vm.mockCall(address(borrowLimitController), IBorrowLimitController.pairLimits.selector, abi.encode(0, 0, 0, 0));
    }

    function _enableWeeklyFeeDistribution() internal {
        vm.mockCall(registry.feeDeposit(), IFeeDeposit.lastDistributedEpoch.selector, abi.encode(0));
        vm.mockCall(registry.getAddress("FEE_DEPOSIT_CONTROLLER"), IFeeDepositController.distribute.selector, bytes(""));
    }

    function _setOnlyDefaultSwapper(address swapper) internal {
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.defaultSwappers.selector, 0), abi.encode(swapper));
        vm.mockCallRevert(address(registry), abi.encodeWithSelector(IResupplyRegistry.defaultSwappers.selector, 1), "index out of bounds");
    }

    function _hasTaskEvent(Vm.Log[] memory logs, bytes32 eventTopic, bytes4 selector, address subject) internal view returns (bool) {
        bytes32 selectorTopic = bytes32(selector);
        bytes32 subjectTopic = bytes32(uint256(uint160(subject)));

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(keeper) && logs[i].topics.length == 3 && logs[i].topics[0] == eventTopic && logs[i].topics[1] == selectorTopic && logs[i].topics[2] == subjectTopic) {
                return true;
            }
        }
        return false;
    }
}
