// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/integration/Setup.sol";
import { RetentionIncentives } from "src/dao/RetentionIncentives.sol";
import { RetentionReceiver } from "src/dao/emissions/receivers/RetentionReceiver.sol";
import { RetentionProgramJsonParser } from "test/utils/RetentionProgramJsonParser.sol";

contract RetentionTest is Setup {
    string public constant RETENTION_JSON_FILE_PATH = "deployment/data/ip_retention_snapshot.json";
    RetentionIncentives public retention;
    RetentionReceiver public receiver;

    uint32 public constant REWARDS_CYCLE_LENGTH = 7 days;
    uint256 public constant TREASURY_WEEKLY_ALLOCATION = 34_255e18;
    IERC20 public asset;

    address[] public retentionUsers;
    uint256[] public retentionAmounts;

    function setUp() public override {
        super.setUp();
        asset = IERC20(address(stablecoin));
        
        _loadRetentionData(false); // true to print values to console
        //deploy retention
        retention = new RetentionIncentives(
            address(core),
            address(registry),
            address(govToken),
            address(insurancePool)
        );
        //set user balances
        retention.setAddressBalances(retentionUsers, retentionAmounts);

        //deploy receiver
        receiver = new RetentionReceiver(
            address(core),
            address(registry),
            address(emissionsController),
            address(retention),
            TREASURY_WEEKLY_ALLOCATION
        );

        // Setup new fee deposit controller
        vm.startPrank(address(core));

        //set reward manager
        retention.setRewardHandler(address(receiver));

        //set emission receiver and weights
        emissionsController.registerReceiver(address(receiver));
        uint256 debtReceiverId = emissionsController.receiverToId(address(debtReceiver));
        uint256 ipReceiverId = emissionsController.receiverToId(address(insuranceEmissionsReceiver));
        uint256 liqReceiverId = emissionsController.receiverToId(address(liquidityEmissionsReceiver));
        uint256 retReceiverId = emissionsController.receiverToId(address(receiver));

        uint256[] memory receivers = new uint256[](4);
        receivers[0] = debtReceiverId;
        receivers[1] = ipReceiverId;
        receivers[2] = liqReceiverId;
        receivers[3] = retReceiverId;
        uint256[] memory weights = new uint256[](4);
        weights[0] = 1875;
        weights[1] = 2500;
        weights[2] = 5000;
        weights[3] = 625;
        emissionsController.setReceiverWeights(receivers,weights);

        //treasury approval
        treasury.setTokenApproval(address(govToken), address(receiver), type(uint256).max);

        vm.stopPrank();
    }

    function test_totalEmissions() public {

        vm.startPrank(address(core));
        //test that claim fails until approval is set
        treasury.setTokenApproval(address(govToken), address(receiver), 0);
        vm.expectRevert();
        receiver.claimEmissions();

        treasury.setTokenApproval(address(govToken), address(receiver), type(uint256).max);
        vm.stopPrank();

        //claim first epoch from treasaury only
        receiver.claimEmissions();
        uint256 receiverDistributed = receiver.distributedRewards();
        //should not increase until next epoch
        console.log("first week distribution: ", receiverDistributed);
        assertEq(receiverDistributed, TREASURY_WEEKLY_ALLOCATION);

        uint256 startEpoch = receiver.getEpoch();
        console.log("starting epoch: ", startEpoch);
        for(uint256 i = 0; i < 52; i++){
            advanceEpochAndClaim();
        }
        uint256 finalEpoch = receiver.getEpoch();
        assertEq(finalEpoch - startEpoch, 52);
        receiverDistributed = receiver.distributedRewards();
        assertEq(receiverDistributed, receiver.MAX_REWARDS());
        console.log("*** RETENTION PROGRAM FINISH ***");

        //ensure new epochs still work and treasury grows
        for(uint256 i = 0; i < 3; i++){
            advanceEpochAndClaim();
        }
    }

    function test_balanceChange() public {
        //print balances
        printBalanceOfUser(retentionUsers[0]);

        //deposit and redeposit
        uint256 ipshares = insurancePool.balanceOf(retentionUsers[0]);
        uint256 retshares = retention.balanceOf(retentionUsers[0]);
        vm.startPrank(retentionUsers[0]);
        insurancePool.exit();
        skip(insurancePool.withdrawTime() + 1);

        insurancePool.redeem(ipshares/2, retentionUsers[0], retentionUsers[0]);
        console.log("redeem");
        printBalanceOfUser(retentionUsers[0]);
        assertEq(retshares, retention.balanceOf(retentionUsers[0])); // no change yet
        
        ipshares = insurancePool.balanceOf(retentionUsers[0]);
        retention.user_checkpoint(retentionUsers[0]);
        console.log("user_checkpoint");
        printBalanceOfUser(retentionUsers[0]);
        assertEq(ipshares, retention.balanceOf(retentionUsers[0])); // should now equal ip shares

        stablecoin.approve(address(insurancePool), type(uint256).max);
        insurancePool.deposit(stablecoin.balanceOf(retentionUsers[0]), retentionUsers[0]);
        console.log("redeposit");
        printBalanceOfUser(retentionUsers[0]);
        retention.user_checkpoint(retentionUsers[0]);
        console.log("user_checkpoint");
        printBalanceOfUser(retentionUsers[0]);

        advanceEpochAndClaim();
        printBalanceOfUser(retentionUsers[0]);
        advanceEpochAndClaim();
        printBalanceOfUser(retentionUsers[0]);
        advanceEpochAndClaim();
        printBalanceOfUser(retentionUsers[0]);

        insurancePool.exit();
        skip(insurancePool.withdrawTime() + 1);
        printBalanceOfUser(retentionUsers[0]);
        insurancePool.redeem(insurancePool.balanceOf(retentionUsers[0]), retentionUsers[0], retentionUsers[0]);
        console.log("redeem all - earned grows until checkpoint");
        advanceEpochAndClaim();
        printBalanceOfUser(retentionUsers[0]);
        advanceEpochAndClaim();
        printBalanceOfUser(retentionUsers[0]);
        retention.user_checkpoint(retentionUsers[0]);
        console.log("user_checkpoint");
        advanceEpochAndClaim();
        printBalanceOfUser(retentionUsers[0]);
        advanceEpochAndClaim();
        printBalanceOfUser(retentionUsers[0]);

    }

    function test_UserClaim() public {
        address user = retentionUsers[0];
        receiver.claimEmissions();
        vestManager.claim(address(treasury));
        advanceEpochAndClaim();
        uint256 userBalance = govToken.balanceOf(user);
        uint256 userEarned = retention.earned(user);
        uint256 retentionBalance = govToken.balanceOf(address(retention));
        printBalanceOfUser(user);
        assertGt(userEarned, 0, "User should have earned rewards");
        vm.prank(user);
        retention.getReward();
        uint256 userBalance2 = govToken.balanceOf(user);
        vm.prank(user);
        retention.getReward();

        assertGt(govToken.balanceOf(user), userBalance, "Balance should increase on claim");
        assertEq(userBalance2, govToken.balanceOf(user), "Balance shouldnt increase on double claim");
        assertEq(govToken.balanceOf(address(retention)), retentionBalance - userEarned, "Retention balance should decrease by user earned");
        assertEq(retention.earned(user), 0, "User earned should be 0");
    }

    // function test_TreasuryIsIlliquid() public {
    //     // Should never revert if treasury is illiquid
    //     uint256 treasuryBalance = govToken.balanceOf(address(treasury));
    //     vm.prank(address(treasury));
    //     govToken.transfer(address(core), treasuryBalance);
    //     assertEq(govToken.balanceOf(address(treasury)), 0);

    //     uint256 totalRewards = govToken.balanceOf(address(retention));
    //     vm.warp(getNextEpochStart());
    //     receiver.claimEmissions();
    //     assertEq(govToken.balanceOf(address(treasury)), 0);
    //     assertGt(govToken.balanceOf(address(retention)), totalRewards, "Retention rewards shouldve gone up");
    // }

    function test_OverFlowIsNeverDistributed() public {
        uint256 TOO_MANY_EPOCHS = 60;
        for(uint256 i = 0; i < TOO_MANY_EPOCHS; i++){
            advanceEpochAndClaim();
        }
        uint256 retentionBalance = govToken.balanceOf(address(retention));
        console.log("Total RSUP distributed to retention: ", retentionBalance);
        assertEq(govToken.balanceOf(address(receiver)), 0);
        assertEq(retentionBalance, receiver.MAX_REWARDS(), "Retention rewards should be exactly max");
    }

    function test_setTreasuryAllocationPerEpoch() public {
        uint256 initialAllocation = receiver.treasuryAllocationPerEpoch();
        uint256 newAllocation = 50_000e18;
        
        // Test permissions
        vm.expectRevert();
        vm.prank(address(1));
        receiver.setTreasuryAllocationPerEpoch(newAllocation);
        
        // Call with owner
        vm.prank(address(core));
        vm.expectEmit(true, true, true, true);
        emit RetentionReceiver.TreasuryAllocationPerEpochSet(newAllocation);
        receiver.setTreasuryAllocationPerEpoch(newAllocation);
        assertEq(receiver.treasuryAllocationPerEpoch(), newAllocation, "Allocation should be updated");
        
        // Test setting to zero
        vm.prank(address(core));
        receiver.setTreasuryAllocationPerEpoch(0);
        assertEq(receiver.treasuryAllocationPerEpoch(), 0, "Allocation should be set to zero");

        advanceEpochAndClaim();
        
        // Test large number
        uint256 largeAllocation = 1_000_000e18;
        vm.prank(address(core));
        receiver.setTreasuryAllocationPerEpoch(largeAllocation);
        assertEq(receiver.treasuryAllocationPerEpoch(), largeAllocation, "Allocation should handle large numbers");
    }

    function printBalanceOfUser(address _account) public{
        console.log("----user balance----");
        console.log("IP balance: ", insurancePool.balanceOf(_account));
        console.log("retention balance: ", retention.balanceOf(_account));
        console.log("earned balance: ", retention.earned(_account));
        console.log("--------");
    }

    function getNextEpochStart() internal view returns (uint256) {
        return (vm.getBlockTimestamp() + REWARDS_CYCLE_LENGTH) / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH;
    }

    function advanceEpochAndClaim() public {
        vm.warp(getNextEpochStart());
        uint256 receiverDistributedBefore = receiver.distributedRewards();
        uint256 treasuryTokensBefore = govToken.balanceOf(address(treasury));
        receiver.claimEmissions();
        vestManager.claim(address(treasury));
        console.log("--- advance epoch ----");
        console.log("epoch: ", receiver.getEpoch());
        uint256 receiverDistributed = receiver.distributedRewards();
        uint256 treasuryTokens = govToken.balanceOf(address(treasury));
        console.log("total distributed: ", receiverDistributed);
        console.log("distributed change: ", receiverDistributed - receiverDistributedBefore);
        if (treasuryTokens > treasuryTokensBefore) {
            console.log("treasury tokens change: ", treasuryTokens - treasuryTokensBefore);
        }
    }

    // Helper function to deposit and return shares
    function depositToIP(address user, uint256 amount) public returns (uint256 shares) {
        deal(address(stablecoin), user, amount);
        vm.startPrank(user);
        stablecoin.approve(address(insurancePool), amount);
        shares = insurancePool.deposit(amount, user);
        vm.stopPrank();
    }

    function exitIP(address user) public {
        vm.startPrank(user);
        insurancePool.exit();
        vm.stopPrank();
    }

    function redeemFromIP(address user, uint256 shares) public returns (uint256 amount) {
        vm.startPrank(user);
        amount = insurancePool.redeem(shares, user, user);
        vm.stopPrank();
    }

    function _loadRetentionData(bool print) internal {
        RetentionProgramJsonParser.RetentionData memory data = 
            RetentionProgramJsonParser.parseRetentionSnapshot(vm.readFile(RETENTION_JSON_FILE_PATH));
        retentionUsers = data.users;
        retentionAmounts = data.amounts;
        if(print) {
            for (uint256 i = 0; i < retentionUsers.length; i++) {
                console.log(i, retentionUsers[i], retentionAmounts[i]);
            }
        }
    }
}