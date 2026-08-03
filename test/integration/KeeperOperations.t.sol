// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
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

contract KeeperOperationsTest is Test {
    uint256 internal constant FORK_BLOCK = 25_674_238;
    uint256 internal constant MIN_PROFIT = 100e18;

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

        keeper.work();

        assertEq(lifi.nextPairIndex(), 21);
        assertEq(enso.nextPairIndex(), 21);
        assertFalse(keeper.canUpdateSwapperApprovals());
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

    function test_UpdateApprovalFailureRevertsWork() public {
        RevertingApprovalUpdater revertingUpdater = new RevertingApprovalUpdater();
        _setOnlyDefaultSwapper(address(revertingUpdater));

        vm.expectRevert(RevertingApprovalUpdater.UpdateFailed.selector);
        keeper.work();
    }

    function test_WorkUpdatesBorrowLimits() public {
        uint256 sdolaPreview = borrowLimitController.previewNewBorrowLimit(address(sdolaPair));
        uint256 sfrxUsdPreview = borrowLimitController.previewNewBorrowLimit(address(sfrxUsdPair));

        assertTrue(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertTrue(keeper.canUpdateBorrowLimit(address(sfrxUsdPair)));

        keeper.work();

        assertEq(sdolaPair.borrowLimit(), sdolaPreview);
        assertEq(sfrxUsdPair.borrowLimit(), sfrxUsdPreview);
        assertFalse(keeper.canUpdateBorrowLimit(address(sdolaPair)));
        assertFalse(keeper.canUpdateBorrowLimit(address(sfrxUsdPair)));
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
        vm.mockCallRevert(address(borrowLimitController), abi.encodeWithSelector(IBorrowLimitController.updatePairBorrowLimit.selector, address(sdolaPair)), "update failed");

        vm.expectRevert("update failed");
        keeper.work();
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
}
