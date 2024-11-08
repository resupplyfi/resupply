
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Setup } from "../utils/Setup.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VestManagerBaseTest is Setup {

    function setUp() public override {
        super.setUp();

        
        vm.prank(address(core));
        govToken.approve(address(vestManager), type(uint256).max);
    }

    function test_CreateVest() public {
        vm.prank(address(core));
        govToken.approve(address(vestManager), type(uint256).max);
        deal(address(govToken), address(core), 1_000_000e18);
        vm.prank(user1);
        vm.expectRevert("!core");
        vestManager.createVest(
            address(core),
            address(user1),
            365 days,
            1_000e18
        );

        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Panic(uint256)")), uint256(0x32)));
        vestManager.getSingleVestData(user1, 0);
        
        // Create vest #1
        uint256 amount = 1_000e18;
        vm.startPrank(address(core));
        vestManager.createVest(address(core), user1, 100 days, amount);

        assertEq(vestManager.numAccountVests(user1), 1);
        (uint256 claimable, uint256 locked, uint256 claimed, uint256 vested) = vestManager.getAggregatedAccountData(user1);
        assertEq(claimable, 0);
        assertEq(claimed, 0);
        assertEq(locked, amount);
        assertEq(vested, 0);

        skip(100 days);

        assertEq(vestManager.numAccountVests(user1), 1);
        (claimable, locked, claimed, vested) = vestManager.getAggregatedAccountData(user1);
        assertEq(claimable, amount);
        assertEq(claimed, 0);
        assertEq(locked, 0);
        assertEq(vested, amount);

        // Create vest #2
        vestManager.createVest(address(core), user1, 100 days, amount);
        vm.stopPrank();

        assertEq(vestManager.numAccountVests(user1), 1);
        (claimable, locked, claimed, vested) = vestManager.getAggregatedAccountData(user1);
        assertEq(claimable, amount * 2);
        assertEq(claimed, 0);
        assertEq(locked, 0);
        assertEq(vested, amount * 2);

        vm.prank(user1);
        vestManager.claim(user1);

        (claimable, locked, claimed, vested) = vestManager.getAggregatedAccountData(user1);
        assertEq(claimable, 0);
        assertEq(claimed, amount * 2);
        assertEq(locked, 0);
        assertEq(vested, amount * 2);

        // Create vest #3
        amount = 50_000e18;
        vm.prank(address(core));
        vestManager.createVest(address(core), user1, 20 days, amount);
        skip(10 days);

        for (uint256 i = 0; i < vestManager.numAccountVests(user1); i++) {
            (claimable, locked, claimed, vested) = vestManager.getSingleVestData(user1, i);
            console.log("----- Vest index ", i, "-----");
            console.log("claimable", claimable);
            console.log("locked", locked);
            console.log("claimed", claimed);
            console.log("vested", vested);
        }

        printAggregatedData(user1);

        vm.expectRevert("!CallerOrDelegated");
        vm.prank(user2);
        vestManager.claim(user1);

        vm.prank(user1);
        vestManager.claim(user1);

        printAggregatedData(user1);
        skip(100 days);
        (claimable, locked, claimed, vested) = vestManager.getAggregatedAccountData(user1);
        assertEq(claimable, vested - claimed);
        assertEq(locked, 0);
        assertEq(vested, claimable + claimed);

    }

    function test_sweepUnclaimed() public {
        vm.startPrank(address(core));

        vm.expectRevert("!deadline");
        vestManager.sweepUnclaimed();

        vm.warp(vestManager.deadline());
        uint256 balance = govToken.balanceOf(address(vestManager));
        
        vestManager.sweepUnclaimed();
        assertEq(govToken.balanceOf(address(vestManager)), 0);
        assertEq(govToken.balanceOf(address(core)), balance);
        vm.stopPrank();
    }

    function printAggregatedData(address _account) public {
        (uint256 claimable, uint256 locked, uint256 claimed, uint256 vested) = vestManager.getAggregatedAccountData(_account);
        console.log("----- Aggregated data -----");
        console.log("claimable", claimable);
        console.log("locked", locked);
        console.log("claimed", claimed);
        console.log("vested", vested);
    }
}
