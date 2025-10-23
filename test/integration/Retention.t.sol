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

    uint32 public constant REWARDS_CYCLE_LENGTH = 7 days;
    uint256 public constant TREASURY_WEEKLY_ALLOCATION = 34_255e18;
    IERC20 public asset;

    address[] public retentionUsers;
    uint256[] public retentionAmounts;

    function setUp() public override {
        super.setUp();
        _loadRetentionData(false); // true to print values to console
        asset = IERC20(address(stablecoin));
        // Setup new fee deposit controller
        vm.startPrank(address(core));

        //set emission receiver and weights
        uint256 debtReceiverId = emissionsController.receiverToId(address(debtReceiver));
        uint256 ipReceiverId = emissionsController.receiverToId(address(insuranceEmissionsReceiver));
        uint256 liqReceiverId = emissionsController.receiverToId(address(liquidityEmissionsReceiver));
        uint256 retReceiverId = emissionsController.receiverToId(address(retentionReceiver));

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

        vm.stopPrank();
    }

    function test_totalEmissions() public {
        advanceEpochAndClaim();
        vm.startPrank(address(core));
        //test that claim fails until approval is set
        treasury.setTokenApproval(address(govToken), address(retentionReceiver), 0);
        vm.expectRevert();
        retentionReceiver.claimEmissions();

        treasury.setTokenApproval(address(govToken), address(retentionReceiver), type(uint256).max);
        vm.stopPrank();

        uint256 startEpoch = retentionReceiver.getEpoch();
        console.log("starting epoch: ", startEpoch);
        for(uint256 i = 0; i < 52; i++){
            advanceEpochAndClaim();
        }
        uint256 finalEpoch = retentionReceiver.getEpoch();
        assertEq(finalEpoch - startEpoch, 52);
        uint256 distributed = retentionReceiver.distributedRewards();
        assertEq(distributed, retentionReceiver.MAX_REWARDS());
        console.log("*** RETENTION PROGRAM FINISH ***");

        //ensure new epochs still work and treasury grows
        for(uint256 i = 0; i < 3; i++){
            advanceEpochAndClaim();
        }
    }

    function test_balanceChange() public {
        if (retention.balanceOf(retentionUsers[0]) == 0) return;
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
        if (retention.balanceOf(retentionUsers[0]) == 0) return;
        advanceEpochAndClaim();
        address user = retentionUsers[0];
        vestManager.claim(address(treasury));
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
        uint256 distributed = retentionReceiver.distributedRewards();
        console.log("Total RSUP distributed to retention: ", distributed);
        assertEq(distributed, retentionReceiver.MAX_REWARDS(), "Retention rewards should be less than max");
    }

    function test_setTreasuryAllocationPerEpoch() public {
        uint256 initialAllocation = retentionReceiver.treasuryAllocationPerEpoch();
        uint256 newAllocation = 50_000e18;
        
        // Test permissions
        vm.expectRevert();
        vm.prank(address(1));
        retentionReceiver.setTreasuryAllocationPerEpoch(newAllocation);
        
        // Call with owner
        vm.prank(address(core));
        vm.expectEmit(true, true, true, true);
        emit RetentionReceiver.TreasuryAllocationPerEpochSet(newAllocation);
        retentionReceiver.setTreasuryAllocationPerEpoch(newAllocation);
        assertEq(retentionReceiver.treasuryAllocationPerEpoch(), newAllocation, "Allocation should be updated");
        
        // Test setting to zero
        vm.prank(address(core));
        retentionReceiver.setTreasuryAllocationPerEpoch(0);
        assertEq(retentionReceiver.treasuryAllocationPerEpoch(), 0, "Allocation should be set to zero");

        advanceEpochAndClaim();
        
        // Test large number
        uint256 largeAllocation = 1_000_000e18;
        vm.prank(address(core));
        retentionReceiver.setTreasuryAllocationPerEpoch(largeAllocation);
        assertEq(retentionReceiver.treasuryAllocationPerEpoch(), largeAllocation, "Allocation should handle large numbers");
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
        uint256 receiverDistributedBefore = retentionReceiver.distributedRewards();
        uint256 treasuryTokensBefore = govToken.balanceOf(address(treasury));
        vestManager.claim(address(treasury));
        console.log("last epoch: ", retentionReceiver.lastEpoch(), "get epoch: ", retentionReceiver.getEpoch());
        vestManager.claim(address(treasury));
        retentionReceiver.claimEmissions();
        console.log("--- advance epoch ----");
        console.log("epoch: ", retentionReceiver.lastEpoch());
        uint256 receiverDistributed = retentionReceiver.distributedRewards();
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