// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Keeper, IOperator } from "src/helpers/keepers/Keeper.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRouterSwapper } from "src/interfaces/IRouterSwapper.sol";
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

    Keeper internal keeper;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"), FORK_BLOCK);
        keeper = new Keeper(address(this), new address[](0), MIN_PROFIT);
    }

    function test_CanWorkWhenSwapperApprovalsNeedUpdate() public view {
        assertTrue(keeper.canUpdateSwapperApprovals());
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

    function _disableSwapperUpdates() internal {
        vm.mockCall(address(lifi), IRouterSwapper.canUpdateApprovals.selector, abi.encode(false));
        vm.mockCall(address(enso), IRouterSwapper.canUpdateApprovals.selector, abi.encode(false));
    }

    function _setOnlyDefaultSwapper(address swapper) internal {
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.defaultSwappers.selector, 0), abi.encode(swapper));
        vm.mockCallRevert(address(registry), abi.encodeWithSelector(IResupplyRegistry.defaultSwappers.selector, 1), "index out of bounds");
    }
}
