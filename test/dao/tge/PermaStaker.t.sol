pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Setup } from "../../Setup.sol";
import { IGovStaker } from "../../../src/interfaces/IGovStaker.sol";
import { GovStaker } from "../../../src/dao/staking/GovStaker.sol";
import { VestManagerInitParams } from "../../helpers/VestManagerInitParams.sol";
import { MockGovStaker } from "../../mocks/MockGovStaker.sol";

contract PermaStakerTest is Setup {

    function setUp() public override {
        super.setUp();
        
        deal(address(govToken), address(permaStaker1), 1000e18);
        deal(address(govToken), address(permaStaker2), 2000e18);

        console.log('govtoken',address(govToken));
        console.log('staketoken',staker.stakeToken());
        uint256 balance = govToken.balanceOf(address(permaStaker1));
        vm.prank(address(permaStaker1));
        staker.stake(address(permaStaker1), balance);

        balance = govToken.balanceOf(address(permaStaker2));
        vm.prank(address(permaStaker2));
        staker.stake(address(permaStaker2), balance);

        skip(staker.epochLength());
    }

    function test_SafeExecute() public {
        vm.prank(permaStaker1.owner());
        permaStaker1.safeExecute(
            address(govToken), 
            abi.encodeWithSelector(govToken.approve.selector, user1, 100e18)
        );

        vm.prank(user2);
        vm.expectRevert("!ownerOrOperator");
        permaStaker1.safeExecute(
            address(govToken), 
            abi.encodeWithSelector(govToken.approve.selector, user1, 100e18)
        );

        vm.expectRevert( "CallFailed");
        vm.prank(user1);
        permaStaker1.safeExecute(
            address(staker), 
            abi.encodeWithSelector(staker.cooldown.selector, address(permaStaker1), 100e18)
        );
    }


    function test_Execute() public {
        vm.expectRevert("!ownerOrOperator");
        permaStaker1.execute(
            address(govToken), 
            abi.encodeWithSelector(
                govToken.approve.selector, 
                address(permaStaker1), 
                100e18
            )
        );

        vm.startPrank(permaStaker1.owner());
        permaStaker1.execute(
            address(govToken), 
            abi.encodeWithSelector(
                govToken.approve.selector, 
                address(permaStaker1), 
                100e18
            )
        );

        permaStaker1.execute(
            address(govToken), 
            abi.encodeWithSelector(
                govToken.transfer.selector, 
                address(permaStaker1), 
                100e18
            )
        );
        vm.stopPrank();
    }

    function test_Stake() public {
        uint256 balance = staker.balanceOf(address(permaStaker1));
        deal(address(govToken), address(permaStaker1), 1000e18);

        uint256 govBalance = govToken.balanceOf(address(permaStaker1));
        vm.startPrank(address(permaStaker1));
        staker.stake(address(permaStaker1), govBalance);
        assertGt(staker.balanceOf(address(permaStaker1)), balance);


        balance = staker.balanceOf(address(permaStaker1));
        deal(address(govToken), address(permaStaker1), 1000e18);
        govBalance = govToken.balanceOf(address(permaStaker1));
        staker.stake(address(permaStaker1), govBalance);
        assertGt(staker.balanceOf(address(permaStaker1)), balance);
        vm.stopPrank();
    }

    function stakeSome() public {
        deal(address(govToken), address(permaStaker1), 1000e18);
        uint256 balance = govToken.balanceOf(address(permaStaker1));
        vm.prank(address(permaStaker1));
        staker.stake(address(permaStaker1), balance);
        assertGt(staker.balanceOf(address(permaStaker1)), 0);
    }

    function test_SetOperator() public {
        vm.prank(permaStaker1.owner());
        permaStaker1.setOperator(address(user1));
        assertEq(permaStaker1.operator(), address(user1));
    }

    function test_CannotCallVestManager() public {
        vm.prank(permaStaker1.owner());
        vm.expectRevert("target not allowed");
        permaStaker1.execute(address(vestManager), "");
    }

    function test_ClaimAndStake() public {
        setupVest();
        skip(10 days); // allow vested amount to grow
        uint256 balance = staker.balanceOf(address(permaStaker1));
        vm.prank(permaStaker1.owner());
        uint256 amount = permaStaker1.claimAndStake();
        assertGt(amount, 0);
        assertEq(
            balance + amount, 
            staker.balanceOf(address(permaStaker1)), 
            "Amount not staked"
        );
    }

    function test_MigrateStakerFromPermaStaker() public {
        setupVest();
        uint256 startAmount = staker.balanceOf(address(permaStaker1));
        skip(10 days); // allow vested amount to grow
        vm.prank(permaStaker1.owner());

        uint256 amount = permaStaker1.claimAndStake();
        assertGt(amount, 0);

        deployNewStakerAndSetInRegistry();

        vm.prank(permaStaker1.owner());
        permaStaker1.migrateStaker();
    }

    function test_MigrateStakerFromPermaStakerAfterManualMigration() public {
        setupVest();
        uint256 startAmount = staker.balanceOf(address(permaStaker1));
        skip(10 days); // allow vested amount to grow
        vm.prank(permaStaker1.owner());
        uint256 amount = permaStaker1.claimAndStake();
        assertGt(amount, 0);
        address newStaker = deployNewStakerAndSetInRegistry();
        vm.prank(address(permaStaker1));
        uint256 amount2 = staker.migrateStake();
        address originalStaker = address(permaStaker1.staker());
        assertNotEq(originalStaker, newStaker);
        // Should not be able to claim to old staker
        vm.prank(permaStaker1.owner());
        vm.expectRevert("Migration needed");
        permaStaker1.claimAndStake();
        // Perform the migration to update the `staker` value in storage
        vm.prank(permaStaker1.owner());
        permaStaker1.migrateStaker();
        address activeStaker = address(permaStaker1.staker());
        assertEq(activeStaker, newStaker);
    }

    function test_MigrateStaker() public {
        setupVest();
        uint256 startAmount = staker.balanceOf(address(permaStaker1));
        skip(10 days); // allow vested amount to grow
        vm.prank(permaStaker1.owner());

        uint256 amount = permaStaker1.claimAndStake();
        assertGt(amount, 0);

        MockGovStaker newStaker = new MockGovStaker(address(core), address(registry), address(govToken), 2, address(staker));
        vm.label(address(newStaker), 'NewStaker');
        vm.prank(address(permaStaker1));
        newStaker.setDelegateApproval(address(staker), true); // Must give approval for migration

        vm.prank(address(core));
        registry.setStaker(address(newStaker));
        vm.prank(address(core));
        staker.setCooldownEpochs(0);

        skip(staker.epochLength());
        staker.checkpointAccount(address(permaStaker1));
        (uint112 realizedStake, uint112 pendingStake,,) = staker.accountData(address(permaStaker1));
        assertEq(newStaker.isPermaStaker(address(permaStaker1)), false, 'should not yet beperma staker');

        vm.prank(address(permaStaker1));
        uint256 amount2 = staker.migrateStake();
        assertEq(amount2, amount + startAmount, 'mismatching amounts migrated vs claimed');
        assertGt(amount2, 0, 'migrated amount not > 0');
        assertEq(staker.balanceOf(address(permaStaker1)), 0, 'old staker balance not 0');
        assertEq(newStaker.balanceOf(address(permaStaker1)), amount + startAmount, 'new staker balance not equal to claimed amount');
        assertEq(newStaker.isPermaStaker(address(permaStaker1)), true, 'perma staker not set');

        MockGovStaker newStaker2 = new MockGovStaker(address(core), address(registry), address(govToken), 2, address(newStaker));
        vm.label(address(newStaker2), 'NewStaker2');
        vm.prank(address(core));
        registry.setStaker(address(newStaker2));
        vm.prank(address(core));
        newStaker.setCooldownEpochs(0);

        skip(staker.epochLength());
        
        vm.startPrank(address(permaStaker1));
        newStaker2.setDelegateApproval(address(newStaker), true); // Must give approval for migration
        newStaker.migrateStake();
        assertEq(newStaker2.balanceOf(address(permaStaker1)), amount + startAmount, 'new staker balance not equal to claimed amount');
        vm.stopPrank();
    }

    function setupVest() public {
        if (!vestManager.initialized()) {
            VestManagerInitParams.InitParams memory params = VestManagerInitParams.getInitParams(
                address(permaStaker1),
                address(permaStaker2),
                address(treasury)
            );
            vm.prank(address(core));
            vestManager.setInitializationParams(
                params.maxRedeemable,      // _maxRedeemable
                params.merkleRoots,
                params.nonUserTargets,
                params.durations,
                params.allocPercentages
            );
        }
    }

    function deployNewStakerAndSetInRegistry() public returns (address) {
        MockGovStaker newStaker = new MockGovStaker(address(core), address(registry), address(govToken), 2, address(staker));
        vm.label(address(newStaker), 'NewStaker');
        vm.prank(address(core));
        registry.setStaker(address(newStaker));
        vm.prank(address(core));
        staker.setCooldownEpochs(0);
        skip(staker.epochLength());
        
        return address(newStaker);
    }
}