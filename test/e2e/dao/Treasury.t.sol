pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { Setup } from "../Setup.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TreasuryTest is Setup {

    function setUp() public override {
        super.setUp();
        deal(address(govToken), address(treasury), 1_000_000 * 10 ** 18);
        deal(address(treasury), 10_000 * 10 ** 18); // ETH
    }

    function test_SetTokenApproval() public {
        vm.prank(address(user1));
        vm.expectRevert(abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientAllowance.selector,
            user1,
            0,
            1
        ));
        govToken.transferFrom(address(treasury), address(user1), 1);

        vm.prank(address(core));
        treasury.setTokenApproval(address(govToken), address(user1), type(uint256).max);
        
        uint256 treasuryBalance = govToken.balanceOf(address(treasury));
        uint256 preBalance = govToken.balanceOf(address(user1));
        vm.prank(address(user1));
        govToken.transferFrom(address(treasury), address(user1), treasuryBalance);
        uint256 postBalance = govToken.balanceOf(address(user1));
        assertEq(postBalance - preBalance, treasuryBalance);
        assertEq(govToken.balanceOf(address(treasury)), 0);
        assertGt(postBalance, preBalance);
    }

    function test_RetrieveETH() public {
        uint256 amount = 1 * 10 ** 18;
        uint256 treasuryPreBalance = address(treasury).balance;
        uint256 user1PreBalance = address(user1).balance;

        vm.expectRevert("!core");
        treasury.retrieveETHExact(address(user1), amount);
        vm.prank(address(core));
        treasury.retrieveETHExact(address(user1), amount);
        uint256 treasuryPostBalance = address(treasury).balance;
        uint256 user1PostBalance = address(user1).balance;

        assertEq(user1PostBalance - user1PreBalance, amount);
        assertEq(treasuryPreBalance - treasuryPostBalance, amount);

        treasuryPreBalance = address(treasury).balance;
        vm.expectRevert("!core");
        treasury.retrieveETH(address(user1));
        vm.prank(address(core));
        treasury.retrieveETH(address(user1));
        treasuryPostBalance = address(treasury).balance;
        assertEq(address(user1).balance, user1PostBalance + treasuryPreBalance);
        assertEq(treasuryPostBalance, 0);
    }

    function test_RetrieveToken() public {
        uint256 amount = 500 * 10 ** 18; // Example token amount
        uint256 treasuryPreBalance = govToken.balanceOf(address(treasury));
        uint256 user1PreBalance = govToken.balanceOf(address(user1));

        vm.expectRevert("!core");
        treasury.retrieveTokenExact(address(govToken), address(user1), amount);
        vm.prank(address(core));
        treasury.retrieveTokenExact(address(govToken), address(user1), amount);
        uint256 treasuryPostBalance = govToken.balanceOf(address(treasury));
        uint256 user1PostBalance = govToken.balanceOf(address(user1));

        assertEq(user1PostBalance - user1PreBalance, amount);
        assertEq(treasuryPreBalance - treasuryPostBalance, amount);

        treasuryPreBalance = govToken.balanceOf(address(treasury));
        user1PreBalance = govToken.balanceOf(address(user1));

        vm.expectRevert("!core");
        treasury.retrieveToken(address(govToken), address(user1));
        vm.prank(address(core));
        treasury.retrieveToken(address(govToken), address(user1));
        treasuryPostBalance = govToken.balanceOf(address(treasury));
        user1PostBalance = govToken.balanceOf(address(user1));

        assertEq(user1PostBalance, user1PreBalance + treasuryPreBalance);
        assertEq(treasuryPostBalance, 0);
    }

    function test_Execute() public {
        vm.expectRevert("!core");
        treasury.safeExecute(address(stablecoin), abi.encodeWithSelector(IERC20.approve.selector, address(user1), type(uint256).max));
        
        vm.expectRevert("!core");
        treasury.execute(address(stablecoin), abi.encodeWithSelector(IERC20.approve.selector, address(user1), type(uint256).max));

        vm.prank(address(core));
        treasury.execute(address(stablecoin), abi.encodeWithSelector(IERC20.approve.selector, address(user1), type(uint256).max));

        vm.prank(address(core));
        treasury.safeExecute(address(stablecoin), abi.encodeWithSelector(IERC20.approve.selector, address(user1), type(uint256).max));
    }
    
}