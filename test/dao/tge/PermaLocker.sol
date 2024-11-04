pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Setup } from "../utils/Setup.sol";
import { MockVestManager } from "../../mocks/MockVestManager.sol";

contract PermaLockerTest is Setup {
    MockVestManager public mockVestManager;

    function setUp() public override {
        super.setUp();
    }

    function test_Execute() public {
        vm.prank(permaLocker1.owner());
        permaLocker1.safeExecute(
            address(govToken), 
            abi.encodeWithSelector(govToken.approve.selector, user1, 100e18)
        );

        vm.prank(user2);
        vm.expectRevert("!ownerOrOperator");
        permaLocker1.safeExecute(
            address(govToken), 
            abi.encodeWithSelector(govToken.approve.selector, user1, 100e18)
        );
    }
}
