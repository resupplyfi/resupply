// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "lib/forge-std/src/Test.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BadDebtPayer } from "src/dao/misc/BadDebtPayer.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";

contract BadDebtPayerTest is Test {
    BadDebtPayer public badDebtPayer;
    
    // Mainnet addresses from BadDebtPayer contract
    address public constant PAIR = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;
    address public constant TOKEN = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
    address public constant BORROWER = 0x151aA63dbb7C605E7b0a173Ab7375e1450E79238;
    address public constant REGISTRY = 0x10101010E0C3171D894B71B3400668aF311e7D94;
    
    // Test user
    address public user = address(0x1);
    
    function setUp() public {
        // Fork mainnet
        vm.createSelectFork("mainnet");
        
        // Deploy BadDebtPayer
        badDebtPayer = new BadDebtPayer();
        
        // Label addresses for better debugging
        vm.label(PAIR, "Pair");
        vm.label(TOKEN, "ReUSD");
        vm.label(BORROWER, "Borrower");
        vm.label(REGISTRY, "Registry");
        vm.label(address(badDebtPayer), "BadDebtPayer");
    }

    function test_BadDebtPayerDeployment() public {
        assertEq(address(badDebtPayer.pair()), PAIR);
        assertEq(address(badDebtPayer.token()), TOKEN);
        assertEq(badDebtPayer.BORROWER(), BORROWER);
        assertEq(address(badDebtPayer.registry()), REGISTRY);
        
        // Check that token approval was set in constructor
        uint256 allowance = IERC20(TOKEN).allowance(address(badDebtPayer), PAIR);
        assertEq(allowance, type(uint256).max);
    }

    function test_VoterAddress() public {
        address voterAddress = badDebtPayer.voter();
        console.log("Voter address:", voterAddress);
        assertTrue(voterAddress != address(0), "Voter address should not be zero");
        
        // Verify it matches the registry's voter address
        IResupplyRegistry registry = IResupplyRegistry(REGISTRY);
        address registryVoter = registry.getAddress("VOTER");
        assertEq(voterAddress, registryVoter);
    }

    function test_PayBadDebtWithValidAmount() public {
        // Get current pair state
        IResupplyPair pair = IResupplyPair(PAIR);
        (uint256 totalBorrow, uint256 totalShares) = pair.totalBorrow();
        
        console.log("Total borrow:", totalBorrow);
        console.log("Total shares:", totalShares);
        
        // Calculate a valid amount (less than total borrow)
        uint256 validAmount = totalBorrow > 0 ? totalBorrow / 2 : 1e18;
        
        // Transfer tokens to user for testing
        deal(TOKEN, user, validAmount);
        
        // Record initial balances and pair state
        uint256 initialUserBalance = IERC20(TOKEN).balanceOf(user);
        uint256 initialBadDebtPayerBalance = IERC20(TOKEN).balanceOf(address(badDebtPayer));
        uint256 initialBorrowerBalance = IERC20(TOKEN).balanceOf(BORROWER);
        (uint256 initialTotalBorrow, uint256 initialTotalShares) = pair.totalBorrow();
        
        console.log("Initial user balance:", initialUserBalance);
        console.log("Initial BadDebtPayer balance:", initialBadDebtPayerBalance);
        console.log("Initial borrower balance:", initialBorrowerBalance);
        console.log("Initial total borrow:", initialTotalBorrow);
        
        // Call payBadDebt
        vm.startPrank(user);
        IERC20(TOKEN).approve(address(badDebtPayer), validAmount);
        badDebtPayer.payBadDebt(validAmount);
        vm.stopPrank();
        
        // Check final balances and pair state
        uint256 finalUserBalance = IERC20(TOKEN).balanceOf(user);
        uint256 finalBadDebtPayerBalance = IERC20(TOKEN).balanceOf(address(badDebtPayer));
        uint256 finalBorrowerBalance = IERC20(TOKEN).balanceOf(BORROWER);
        (uint256 finalTotalBorrow, uint256 finalTotalShares) = pair.totalBorrow();
        
        console.log("Final user balance:", finalUserBalance);
        console.log("Final BadDebtPayer balance:", finalBadDebtPayerBalance);
        console.log("Final borrower balance:", finalBorrowerBalance);
        console.log("Final total borrow:", finalTotalBorrow);
        
        // User should have transferred tokens
        assertLt(finalUserBalance, initialUserBalance);
        
        // BadDebtPayer should have no tokens left (all used for repayment)
        assertEq(finalBadDebtPayerBalance, 0);
        
        // Total borrow in the pair should have decreased
        assertLt(finalTotalBorrow, initialTotalBorrow, "Total borrow should have decreased");
        
        console.log("Borrow reduction:", initialTotalBorrow - finalTotalBorrow);
    }

    function test_PayBadDebtWithExcessiveAmount() public {
        // Get current pair state
        IResupplyPair pair = IResupplyPair(PAIR);
        (uint256 totalBorrow, uint256 totalShares) = pair.totalBorrow();
        
        // Use an amount greater than total borrow
        uint256 excessiveAmount = totalBorrow + 1e18;
        
        // Transfer tokens to user for testing
        deal(TOKEN, user, excessiveAmount);
        
        // Get voter address for overflow check
        address voterAddress = badDebtPayer.voter();
        uint256 initialVoterBalance = IERC20(TOKEN).balanceOf(voterAddress);
        
        console.log("Total borrow:", totalBorrow);
        console.log("Excessive amount:", excessiveAmount);
        console.log("Initial voter balance:", initialVoterBalance);
        
        // Call payBadDebt
        vm.startPrank(user);
        IERC20(TOKEN).approve(address(badDebtPayer), excessiveAmount);
        badDebtPayer.payBadDebt(excessiveAmount);
        vm.stopPrank();
        
        // Check that overflow was sent to voter
        uint256 finalVoterBalance = IERC20(TOKEN).balanceOf(voterAddress);
        uint256 expectedOverflow = excessiveAmount - totalBorrow;
        
        console.log("Final voter balance:", finalVoterBalance);
        console.log("Expected overflow:", expectedOverflow);
        
        assertEq(finalVoterBalance, initialVoterBalance + expectedOverflow);
        
        // BadDebtPayer should have no tokens left
        uint256 finalBadDebtPayerBalance = IERC20(TOKEN).balanceOf(address(badDebtPayer));
        assertEq(finalBadDebtPayerBalance, 0);
    }

    function test_PayBadDebtWithZeroAmount() public {
        // Transfer some tokens to user
        deal(TOKEN, user, 1e18);
        
        // Record initial balances
        uint256 initialUserBalance = IERC20(TOKEN).balanceOf(user);
        uint256 initialBadDebtPayerBalance = IERC20(TOKEN).balanceOf(address(badDebtPayer));
        
        // Call payBadDebt with zero amount
        vm.startPrank(user);
        IERC20(TOKEN).approve(address(badDebtPayer), 0);
        badDebtPayer.payBadDebt(0);
        vm.stopPrank();
        
        // Balances should remain unchanged
        uint256 finalUserBalance = IERC20(TOKEN).balanceOf(user);
        uint256 finalBadDebtPayerBalance = IERC20(TOKEN).balanceOf(address(badDebtPayer));
        
        assertEq(finalUserBalance, initialUserBalance);
        assertEq(finalBadDebtPayerBalance, initialBadDebtPayerBalance);
    }

    function test_RecoverERC20() public {
        // Transfer some tokens to BadDebtPayer
        uint256 recoveryAmount = 1e18;
        deal(TOKEN, address(badDebtPayer), recoveryAmount);
        
        // Get core address from registry
        IResupplyRegistry registry = IResupplyRegistry(REGISTRY);
        address coreAddress = registry.core();
        
        uint256 initialCoreBalance = IERC20(TOKEN).balanceOf(coreAddress);
        uint256 initialBadDebtPayerBalance = IERC20(TOKEN).balanceOf(address(badDebtPayer));
        
        console.log("Initial core balance:", initialCoreBalance);
        console.log("Initial BadDebtPayer balance:", initialBadDebtPayerBalance);
        
        // Call recoverERC20
        badDebtPayer.recoverERC20(TOKEN);
        
        // Check final balances
        uint256 finalCoreBalance = IERC20(TOKEN).balanceOf(coreAddress);
        uint256 finalBadDebtPayerBalance = IERC20(TOKEN).balanceOf(address(badDebtPayer));
        
        console.log("Final core balance:", finalCoreBalance);
        console.log("Final BadDebtPayer balance:", finalBadDebtPayerBalance);
        
        // Core should have received the tokens
        assertEq(finalCoreBalance, initialCoreBalance + recoveryAmount);
        
        // BadDebtPayer should have no tokens left
        assertEq(finalBadDebtPayerBalance, 0);
    }

    function test_RecoverERC20WithZeroBalance() public {
        // Ensure BadDebtPayer has no tokens
        uint256 initialBalance = IERC20(TOKEN).balanceOf(address(badDebtPayer));
        if (initialBalance > 0) {
            badDebtPayer.recoverERC20(TOKEN);
        }
        
        // Get core address from registry
        IResupplyRegistry registry = IResupplyRegistry(REGISTRY);
        address coreAddress = registry.core();
        
        uint256 initialCoreBalance = IERC20(TOKEN).balanceOf(coreAddress);
        
        // Call recoverERC20 when BadDebtPayer has no balance
        badDebtPayer.recoverERC20(TOKEN);
        
        // Core balance should remain unchanged
        uint256 finalCoreBalance = IERC20(TOKEN).balanceOf(coreAddress);
        assertEq(finalCoreBalance, initialCoreBalance);
    }

    function test_PayBadDebtRevertScenarios() public {
        // Test with insufficient allowance
        vm.startPrank(user);
        deal(TOKEN, user, 1e18);
        
        // Don't approve tokens
        vm.expectRevert();
        badDebtPayer.payBadDebt(1e18);
        
        vm.stopPrank();
    }

    function test_GasUsage() public {
        // Get current pair state
        IResupplyPair pair = IResupplyPair(PAIR);
        (uint256 totalBorrow, ) = pair.totalBorrow();
        
        // Use a reasonable amount for gas testing
        uint256 testAmount = totalBorrow > 0 ? totalBorrow / 4 : 1e18;
        
        // Transfer tokens to user
        deal(TOKEN, user, testAmount);
        
        // Measure gas usage for payBadDebt
        vm.startPrank(user);
        IERC20(TOKEN).approve(address(badDebtPayer), testAmount);
        
        uint256 gasBefore = gasleft();
        badDebtPayer.payBadDebt(testAmount);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for payBadDebt:", gasUsed);
        console.log("Amount processed:", testAmount);
        
        vm.stopPrank();
        
        // Measure gas usage for recoverERC20
        deal(TOKEN, address(badDebtPayer), 1e18);
        
        gasBefore = gasleft();
        badDebtPayer.recoverERC20(TOKEN);
        gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for recoverERC20:", gasUsed);
    }
} 