// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/integration/Setup.sol";
import { RetentionIncentives } from "src/dao/RetentionIncentives.sol";
import { RetentionReceiver } from "src/dao/emissions/receivers/RetentionReceiver.sol";

contract RetentionTest is Setup {
    RetentionIncentives public retention;
    RetentionReceiver public receiver;

    uint32 public constant REWARDS_CYCLE_LENGTH = 7 days;
    IERC20 public asset;

    address userA;
    address userB;
    address userC;

    function setUp() public override {
        super.setUp();
        asset = IERC20(address(stablecoin));

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

        //add users
        //TODO read from full user list
        address[] memory users = new address[](3);
        uint256[] memory balances = new uint256[](3);

        users[0] = address(0x00c04AE980A41825FCb505797d394090295B5813);
        users[1] = address(0x9D269CAF80970C7E854c99db8B0c20868825546b);
        users[2] = address(0x6Da40065b15954A3a72375DdC2D57743EB301a05);

        balances[0] = insurancePool.balanceOf(users[0]);
        balances[1] = insurancePool.balanceOf(users[1]);
        balances[2] = insurancePool.balanceOf(users[2]);

        userA = users[0];
        userB = users[1];
        userC = users[2];
        retention.setAddressBalances(users, balances);

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
        printBalanceOfUser(userA);
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
}