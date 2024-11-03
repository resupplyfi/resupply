pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Setup } from "../utils/Setup.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockVestManager } from "../../mocks/MockVestManager.sol";

contract VestingTest is Setup {
    MockVestManager public mockVestManager;

    function setUp() public override {
        super.setUp();

        mockVestManager = new MockVestManager(address(vesting));
        vm.prank(address(core));
        vesting.setVestManager(address(mockVestManager));
        assertEq(address(mockVestManager), address(vesting.vestManagerContract()));
    }

    function test_CreateVest() public {
        vm.startPrank(user1);
        vm.expectRevert("!vestManager");
        vesting.createVest(address(this), block.timestamp, 365 days, 1_000e18);

        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Panic(uint256)")), uint256(0x32)));
        vesting.getSingleVestData(user1, 0);
        
        // Create vest #1
        uint256 amount = 1_000e18;
        mockVestManager.createVest(user1, 100 days, amount);
        vm.stopPrank();

        assertEq(vesting.numAccountVests(user1), 1);
        (uint256 claimable, uint256 locked, uint256 claimed, uint256 vested) = vesting.getAggregatedAccountData(user1);
        assertEq(claimable, 0);
        assertEq(claimed, 0);
        assertEq(locked, amount);
        assertEq(vested, 0);

        skip(100 days);

        assertEq(vesting.numAccountVests(user1), 1);
        (claimable, locked, claimed, vested) = vesting.getAggregatedAccountData(user1);
        assertEq(claimable, amount);
        assertEq(claimed, 0);
        assertEq(locked, 0);
        assertEq(vested, amount);

        // Create vest #2
        mockVestManager.createVest(user1, 100 days, amount);
        vm.stopPrank();

        assertEq(vesting.numAccountVests(user1), 2);
        (claimable, locked, claimed, vested) = vesting.getAggregatedAccountData(user1);
        assertEq(claimable, amount * 1);
        assertEq(claimed, 0);
        assertEq(locked, amount * 1);
        assertEq(vested, amount * 1);

        vm.prank(user1);
        vesting.claim(user1);

        (claimable, locked, claimed, vested) = vesting.getAggregatedAccountData(user1);
        assertEq(claimable, 0);
        assertEq(claimed, amount * 1);
        assertEq(locked, amount * 1);
        assertEq(vested, amount * 1);

        // Create vest #3
        amount = 50_000e18;
        mockVestManager.createVest(user1, 20 days, amount);
        vm.stopPrank();

        skip(10 days);

        for (uint256 i = 0; i < vesting.numAccountVests(user1); i++) {
            (claimable, locked, claimed, vested) = vesting.getSingleVestData(user1, i);
            console.log("----- Vest index ", i, "-----");
            console.log("claimable", claimable);
            console.log("locked", locked);
            console.log("claimed", claimed);
            console.log("vested", vested);
        }

        printAggregatedData(user1);

        vm.expectRevert("!CallerOrDelegated");
        vesting.claim(user1);

        vm.prank(user1);
        vesting.claim(user1);

        printAggregatedData(user1);
        skip(100 days);
        (claimable, locked, claimed, vested) = vesting.getAggregatedAccountData(user1);
        assertEq(claimable, vested - claimed);
        assertEq(locked, 0);
        assertEq(vested, claimable + claimed);
    }

    function test_sweepUnclaimed() public {
        vm.startPrank(address(core));

        vm.expectRevert("!deadline");
        vesting.sweepUnclaimed();

        vm.warp(vesting.deadline());
        uint256 balance = govToken.balanceOf(address(vesting));
        
        vesting.sweepUnclaimed();
        assertEq(govToken.balanceOf(address(vesting)), 0);
        assertEq(govToken.balanceOf(address(core)), balance);
        vm.stopPrank();
    }

    function printAggregatedData(address _account) public {
        (uint256 claimable, uint256 locked, uint256 claimed, uint256 vested) = vesting.getAggregatedAccountData(_account);
        console.log("----- Aggregated data -----");
        console.log("claimable", claimable);
        console.log("locked", locked);
        console.log("claimed", claimed);
        console.log("vested", vested);
    }
}
