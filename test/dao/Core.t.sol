pragma solidity ^0.8.22;

import { Setup } from "../Setup.sol";
import { MockOperator } from "../mocks/MockOperator.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";

contract CoreTest is Setup {
    MockOperator operator;

    function setUp() public override {
        super.setUp();
        operator = new MockOperator(address(core));
    }

    function test_execute() public {
        setupOperator();
        operator.setExpectedValue(1);
    
        vm.prank(address(operator));
        core.execute(address(operator), abi.encodeWithSelector(bytes4(keccak256("setValue(uint256)")), 1));

        vm.prank(address(operator));
        vm.expectRevert('Auth PostHook Failed');
        core.execute(address(operator), abi.encodeWithSelector(bytes4(keccak256("setValue(uint256)")), 2));
    }

    function test_execute_revert() public {
        vm.expectRevert('!authorized');
        core.execute(address(operator), abi.encodeWithSelector(bytes4(keccak256("setValue(uint256)")), 1));
    }

    function setupOperator() internal {
        vm.prank(address(core));
        core.setOperatorPermissions(
            address(operator), 
            address(operator), 
            bytes4(keccak256("setValue(uint256)")), 
            true, 
            IAuthHook(address(operator))
        );
    }
}
