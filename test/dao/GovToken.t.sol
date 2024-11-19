pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { Setup } from "../Setup.sol";

contract TreasuryTest is Setup {

    function setUp() public override {
        super.setUp();
        
        // clear balance of user 1
        uint256 balance = govToken.balanceOf(user1);
        vm.prank(user1);
        govToken.transfer(address(treasury), balance);
    }

    function test_SetMinter() public {
        vm.prank(address(core));
        govToken.setMinter(address(user1));

        vm.prank(address(user1));
        govToken.mint(address(user1), 1000);
        assertEq(govToken.balanceOf(address(user1)), 1000);

        vm.prank(address(core));
        vm.expectRevert("!minter");
        govToken.mint(address(user1), 1000);

        vm.prank(address(core));
        govToken.setMinter(address(user2));

        vm.prank(address(core));
        govToken.finalizeMinter();

        vm.prank(address(core));
        vm.expectRevert("minter finalized");
        govToken.setMinter(address(user1));

        vm.prank(address(core));
        vm.expectRevert("minter finalized");
        govToken.finalizeMinter();
    }
}