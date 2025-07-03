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
        
        _loadRetentionData(true); // true to print values to console
        //deploy retention
        retention = new RetentionIncentives(
            address(core),
            address(registry),
            address(govToken),
            address(insurancePool)
        );

        //deploy receiver
        receiver = new RetentionReceiver(
            address(core),
            address(registry),
            address(emissionsController),
            address(retention)
        );

        // Setup new fee deposit controller
        vm.startPrank(address(core));

        //set manager
        retention.setRewardHandler(address(receiver));
        retention.setAddressBalances(retentionUsers, retentionAmounts);

        //finalize
        retention.finalize();

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
        weights[0] = 2000; //todo get finalized weighting
        weights[1] = 2500;
        weights[2] = 5000;
        weights[3] = 500; //todo get finalized weighting
        emissionsController.setReceiverWeights(receivers,weights);

        //treasury approval
        treasury.setTokenApproval(address(govToken), address(receiver), type(uint256).max);

        vm.stopPrank();
    }


    function test_totalEmissions() public {
        //todo
    }

    function test_balanceChange() public {
        //todo
        printBalanceOfUser(retentionUsers[0]);
    }

    function printBalanceOfUser(address _account) public{
        console.log("----user balance----");

        console.log("IP balance: ", insurancePool.balanceOf(_account));
        console.log("retention balance: ", retention.balanceOf(_account));
        console.log("--------");
    }


    function advanceEpochs(uint256 epochs) public {
        uint256 newEpochTs = block.timestamp / REWARDS_CYCLE_LENGTH * REWARDS_CYCLE_LENGTH + (REWARDS_CYCLE_LENGTH * epochs);
        vm.warp(newEpochTs);
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