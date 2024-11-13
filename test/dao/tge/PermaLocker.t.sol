pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Setup } from "../utils/Setup.sol";
import { IGovStaker } from "../../../src/interfaces/IGovStaker.sol";
import { GovStaker } from "../../../src/dao/staking/GovStaker.sol";

contract PermaLockerTest is Setup {

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

    function test_SafeExecute() public {
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

    function test_Execute() public {
        vm.expectRevert("!ownerOrOperator");
        permaLocker1.execute(
            address(govToken), 
            abi.encodeWithSelector(
                govToken.approve.selector, 
                address(permaLocker1), 
                100e18
            )
        );

        vm.startPrank(permaLocker1.owner());
        permaLocker1.execute(
            address(govToken), 
            abi.encodeWithSelector(
                govToken.approve.selector, 
                address(permaLocker1), 
                100e18
            )
        );

        permaLocker1.execute(
            address(govToken), 
            abi.encodeWithSelector(
                govToken.transfer.selector, 
                address(permaLocker1), 
                100e18
            )
        );
        vm.stopPrank();
    }

    function test_AllowUnstaking() public {
        vm.prank(permaLocker1.owner());
        vm.expectRevert("!core");
        permaLocker1.allowUnstaking(true);

        vm.prank(address(core));
        permaLocker1.allowUnstaking(true);
    }

    function test_Stake() public {
        uint256 balance = staker.balanceOf(address(permaLocker1));
        deal(address(govToken), address(permaLocker1), 1000e18);

        vm.startPrank(permaLocker1.owner());
        permaLocker1.stake();
        assertGt(staker.balanceOf(address(permaLocker1)), balance);


        balance = staker.balanceOf(address(permaLocker1));
        deal(address(govToken), address(permaLocker1), 1000e18);
        permaLocker1.stake(1000e18);
        assertGt(staker.balanceOf(address(permaLocker1)), balance);
        vm.stopPrank();
    }

    function stakeSome() public {
        deal(address(govToken), address(permaLocker1), 1000e18);
        vm.prank(permaLocker1.owner());
        permaLocker1.stake();
        assertGt(staker.balanceOf(address(permaLocker1)), 0);
    }

    function test_SetOperator() public {
        vm.prank(permaLocker1.owner());
        permaLocker1.setOperator(address(user1));
        assertEq(permaLocker1.operator(), address(user1));
    }
}
