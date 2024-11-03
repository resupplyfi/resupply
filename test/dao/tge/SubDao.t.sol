pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Setup } from "../utils/Setup.sol";
import { MockVestManager } from "../../mocks/MockVestManager.sol";

contract SubDaoTest is Setup {
    MockVestManager public mockVestManager;

    function setUp() public override {
        super.setUp();
    }

    function test_Execute() public {
        vm.prank(subdao1.owner());
        subdao1.safeExecute(
            address(govToken), 
            abi.encodeWithSelector(govToken.approve.selector, user1, 100e18)
        );

        vm.prank(user2);
        vm.expectRevert("Ownable: caller is not the owner");
        subdao1.safeExecute(
            address(govToken), 
            abi.encodeWithSelector(govToken.approve.selector, user1, 100e18)
        );
    }
}
