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
            34_255e18
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

        receiver.setStartEpoch();

        vm.stopPrank();
    }

    function test_totalEmissions() public {

        //claim fail until next epoch
        vm.expectRevert();
        receiver.claimEmissions();
        uint256 receiverDistributed = receiver.distributedRewards();
        //should not increase until next epoch
        assertEq(receiverDistributed, 0);

        uint256 startEpoch = receiver.getEpoch() + 1; //will begin the following epoch
       for(uint256 i = 0; i < 53; i++){
            advanceEpochs();
        }
        uint256 finalEpoch = receiver.getEpoch();
        assertEq(finalEpoch - startEpoch, 52);
        receiverDistributed = receiver.distributedRewards();
        assertEq(receiverDistributed, receiver.MAX_REWARDS());
        console.log("*** RETENTION PROGRAM FINISH ***");

        //ensure new epochs still work and treasury grows
        for(uint256 i = 0; i < 3; i++){
            advanceEpochs();
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

        advanceEpochs();
        printBalanceOfUser(retentionUsers[0]);
        advanceEpochs();
        printBalanceOfUser(retentionUsers[0]);
        advanceEpochs();
        printBalanceOfUser(retentionUsers[0]);

        insurancePool.exit();
        skip(insurancePool.withdrawTime() + 1);
        printBalanceOfUser(retentionUsers[0]);
        insurancePool.redeem(insurancePool.balanceOf(retentionUsers[0]), retentionUsers[0], retentionUsers[0]);
        console.log("redeem all - earned grows until checkpoint");
        advanceEpochs();
        printBalanceOfUser(retentionUsers[0]);
        advanceEpochs();
        printBalanceOfUser(retentionUsers[0]);
        retention.user_checkpoint(retentionUsers[0]);
        console.log("user_checkpoint");
        advanceEpochs();
        printBalanceOfUser(retentionUsers[0]);
        advanceEpochs();
        printBalanceOfUser(retentionUsers[0]);

    }

    function printBalanceOfUser(address _account) public{
        console.log("----user balance----");

        console.log("IP balance: ", insurancePool.balanceOf(_account));
        console.log("retention balance: ", retention.balanceOf(_account));
        console.log("earned balance: ", retention.earned(_account));
        console.log("--------");
    }

    function getNextEpochStart() internal view returns (uint256) {
        // Calculate the next epoch boundary
        uint256 nextEpochStart = (block.timestamp + REWARDS_CYCLE_LENGTH) / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH;
        uint256 currentEpochStart = block.timestamp / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH;
        uint256 currentEpoch = block.timestamp / REWARDS_CYCLE_LENGTH;
        uint256 nextEpoch = (block.timestamp + REWARDS_CYCLE_LENGTH) / REWARDS_CYCLE_LENGTH;
        // console.log("------------- ", currentEpoch, " -------------");
        // console.log("Current timestamp:", block.timestamp);
        // console.log("Next epoch start:", nextEpochStart);
        // console.log("Diff:", nextEpochStart - block.timestamp);
        // console.log("Epoch length:", REWARDS_CYCLE_LENGTH);
        // console.log("Current epoch start/end:", currentEpochStart, "-->", nextEpochStart);
        return nextEpochStart;
    }

    function advanceEpochs() public {
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
        console.log("treasury tokens change: ", treasuryTokens - treasuryTokensBefore);
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