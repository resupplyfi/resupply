pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { Setup } from "./utils/Setup.sol";
import { MockPair } from "../mocks/MockPair.sol";

contract CoreTest is Setup {
    MockPair pair;

    function setUp() public override {
        super.setUp();
        pair = new MockPair(address(core));
    }

    function test_Pausable() public {
        vm.startPrank(address(core));
        core.pauseProtocol();
        vm.expectRevert("Already Paused");
        core.pauseProtocol();

        vm.expectRevert("Protocol Paused");
        pair.setValue(1);

        core.unpauseProtocol();

        vm.expectRevert("Already Unpaused");
        core.unpauseProtocol();

        pair.setValue(1);
        vm.stopPrank();
    }
}
