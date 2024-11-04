pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Setup } from "../utils/Setup.sol";
import { MockVestManager } from "../../mocks/MockVestManager.sol";
import { IGovStaker } from "../../../src/interfaces/IGovStaker.sol";
import { GovStaker } from "../../../src/dao/staking/GovStaker.sol";

contract PermaLockerTest is Setup {
    MockVestManager public mockVestManager;

    function setUp() public override {
        super.setUp();
        
        deal(address(govToken), address(permaLocker1), 1000e18);
        deal(address(govToken), address(permaLocker2), 2000e18);

        console.log('govtoken',address(govToken));
        console.log('staketoken',staker.stakeToken());
        vm.prank(permaLocker1.owner());
        permaLocker1.stake();

        vm.prank(permaLocker2.owner());
        permaLocker2.stake();

        skip(staker.epochLength());
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

        vm.expectRevert("UnstakingForbidden");
        vm.prank(user1);
        permaLocker1.safeExecute(
            address(staker), 
            abi.encodeWithSelector(staker.cooldown.selector, address(permaLocker1), 100e18)
        );
    }

    function test_MigrateStaker() public {
        IGovStaker oldStaker = permaLocker1.staker();
        console.log('oldStaker',address(oldStaker));
        assertGt(oldStaker.balanceOf(address(permaLocker1)), 0);

        GovStaker newStaker = new GovStaker(address(core), address(govToken), 1);

        vm.prank(address(core));
        registry.setStaker(address(newStaker));

        vm.prank(permaLocker1.owner());
        permaLocker1.migrateStaker();

        vm.prank(permaLocker1.owner());
        permaLocker1.safeExecute(
            address(oldStaker), 
            abi.encodeWithSelector(
                oldStaker.exit.selector, 
                address(permaLocker1)
            )
        );
    }
}
