pragma solidity ^0.8.22;

import { Setup } from "../Setup.sol";
import { MockPair } from "../mocks/MockPair.sol";
import { Core } from "src/dao/Core.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
contract CoreTest is Setup {
    MockPair pair;

    function setUp() public override {
        super.setUp();
        pair = new MockPair(address(core));
    }

    function test_SetVoter() public {
        assertNotEq(core.voter(), address(tempGov));
        vm.prank(address(voter));
        vm.expectEmit(address(core));
        emit Core.VoterSet(address(tempGov));
        core.execute(
            address(core), 
            abi.encodeWithSelector(core.setVoter.selector, address(tempGov))
        );
        assertEq(core.voter(), address(tempGov));
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

    function test_OperatorPermissions() public {
        vm.prank(address(core));
        core.setOperatorPermissions(
            address(tempGov), 
            address(pair), 
            bytes4(keccak256("setValue(uint256)")), 
            true, 
            IAuthHook(address(0))
        );

        assertNotEq(pair.value(), 1);
        vm.prank(address(tempGov));
        core.execute(
            address(pair), 
            abi.encodeWithSelector(pair.setValue.selector, 1)
        );
        assertEq(pair.value(), 1);
    }
}
