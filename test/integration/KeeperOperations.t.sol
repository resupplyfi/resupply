// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { Keeper, IOperator } from "src/helpers/keepers/Keeper.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRouterSwapper } from "src/interfaces/IRouterSwapper.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
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

contract KeeperOperationsTest is Test {
    uint256 internal constant FORK_BLOCK = 25_674_238;
    uint256 internal constant MIN_PROFIT = 100e18;
    bytes32 internal constant TASK_COMPLETED_TOPIC = keccak256("TaskCompleted(bytes4,address)");
    bytes32 internal constant TASK_FAILED_TOPIC = keccak256("TaskFailed(bytes4,address)");

    IResupplyRegistry internal constant registry = IResupplyRegistry(Protocol.REGISTRY);
    IRouterSwapper internal constant lifi = IRouterSwapper(0x597Db76794c75E588D3a70534FB34B7780941fCe);
    IRouterSwapper internal constant enso = IRouterSwapper(0x181c98113ce60BA75A0f72d8901Eb17e5065043D);
    IOperator internal constant operator = IOperator(0x21862cA8d044c104ac9EB728c86Bc38B8625BeCD);
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

    function test_CanWorkWhenOperatorProfitIsAvailable() public {
        _disableSwapperUpdates();
        _disableBorrowLimitUpdates();
        assertFalse(keeper.canUpdateSwapperApprovals());
        assertFalse(keeper.canWork());

        address[] memory operators = new address[](1);
        operators[0] = address(operator);
        keeper.setOperators(operators, MIN_PROFIT);

        assertGt(operator.profit(), MIN_PROFIT);
        assertTrue(keeper.canWork());
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
        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertFalse(keeper.canUpdateBorrowLimit(address(sfrxUsdPair)));
        assertTrue(_hasTaskEvent(logs, TASK_COMPLETED_TOPIC, IBorrowLimitController.updatePairBorrowLimit.selector, address(sdolaPair)));
        assertTrue(_hasTaskEvent(logs, TASK_COMPLETED_TOPIC, IBorrowLimitController.updatePairBorrowLimit.selector, address(sfrxUsdPair)));
    }

    function test_BorrowLimitUpdatesAreRateLimited() public {
        keeper.work();

        skip(12 hours);
        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertFalse(keeper.canUpdateBorrowLimit(address(sfrxUsdPair)));
        assertFalse(keeper.canWork());

        IBorrowLimitController.PairBorrowLimit memory limit = borrowLimitController.pairLimits(address(sdolaPair));
        skip((limit.endTime - limit.startTime) / 10_000 + 1);
        assertTrue(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertTrue(keeper.canUpdateBorrowLimit(address(sfrxUsdPair)));
        assertTrue(keeper.canWork());
    }

    function test_SkipsPausedBorrowLimitRamp() public view {
        IBorrowLimitController.PairBorrowLimit memory limit = borrowLimitController.pairLimits(address(pausedFxSavePair));

        assertGt(limit.startTime, 0);
        assertEq(pausedFxSavePair.borrowLimit(), 0);
        assertFalse(keeper.canUpdateBorrowLimit(address(pausedFxSavePair)));
    }

    function test_ExternalBorrowLimitUpdateResetsInterval() public {
        borrowLimitController.updatePairBorrowLimit(address(sdolaPair));
        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));

        skip(12 hours);
        borrowLimitController.updatePairBorrowLimit(address(sdolaPair));
        uint256 externallyUpdatedLimit = sdolaPair.borrowLimit();

        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        keeper.work();
        assertEq(sdolaPair.borrowLimit(), externallyUpdatedLimit);
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

    function test_RevertingProfitProbeRevertsCanWork() public {
        _disableSwapperUpdates();
        _disableBorrowLimitUpdates();
        assertFalse(keeper.canWork());

        address[] memory operators = new address[](1);
        operators[0] = address(new RevertingProfitOperator());
        keeper.setOperators(operators, MIN_PROFIT);

        vm.expectRevert(RevertingProfitOperator.ProbeFailed.selector);
        keeper.canWork();
    }

    function _disableSwapperUpdates() internal {
        vm.mockCall(address(lifi), IRouterSwapper.canUpdateApprovals.selector, abi.encode(false));
        vm.mockCall(address(enso), IRouterSwapper.canUpdateApprovals.selector, abi.encode(false));
    }

    function _disableBorrowLimitUpdates() internal {
        vm.mockCall(address(borrowLimitController), IBorrowLimitController.pairLimits.selector, abi.encode(0, 0, 0, 0));
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
