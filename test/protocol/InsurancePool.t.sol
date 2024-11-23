pragma solidity ^0.8.22;

import "forge-std/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/Setup.sol";
import { SimpleReceiverFactory } from "src/dao/emissions/receivers/SimpleReceiverFactory.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { GovToken } from "src/dao/GovToken.sol";
import { EmissionsController } from "src/dao/emissions/EmissionsController.sol";

contract InsurancePoolTest is Setup {
    uint256 public defaultAmount = 10_000e18;

    function setUp() public override {
        super.setUp();

        stablecoin.approve(address(insurancePool), type(uint256).max);
        deal(address(stablecoin), address(this), defaultAmount);
        vm.prank(address(core));
        insurancePool.setWithdrawTimers(1 days, 1 days);

        // Setup emissions
        emissionsController = new EmissionsController(
            address(core),
            address(govToken),
            getEmissionsSchedule(),
            1,
            0,
            0
        );
        vm.startPrank(address(core));
        govToken.setMinter(address(emissionsController));
        emissionsController.registerReceiver(address(ipEmissionStream));
        vm.stopPrank();
    }

    function test_SetWithdrawTimers() public {
        uint256 amount = 10_000e18;
        depositSome(amount);
        vm.prank(address(core));
        insurancePool.setWithdrawTimers(1 days, 1 days);

        insurancePool.exit();

        uint256 balance = insurancePool.balanceOf(address(this));
        vm.expectRevert("!withdraw time");
        insurancePool.redeem(
            balance, 
            address(this), 
            address(this)
        );

        skip(1 days);

        uint256 withdrawn = insurancePool.redeem(
            insurancePool.balanceOf(address(this)) / 2, 
            address(this), 
            address(this)
        );
        assertEq(withdrawn, amount / 2);

        skip(1 days);

        insurancePool.exit();
        skip(
            insurancePool.withdrawTime() + 
            insurancePool.withdrawTimeLimit() +
            1
        );

        balance = insurancePool.balanceOf(address(this));
        vm.expectRevert("withdraw time over");
        insurancePool.redeem(
            balance, // Remainder
            address(this), 
            address(this)
        );
        assertGt(insurancePool.balanceOf(address(this)), 0);
    }

    function test_Mint() public {
        uint256 minted = insurancePool.mint(defaultAmount, address(this));
        assertGt(minted, 0);
        assertEq(insurancePool.convertToAssets(minted), defaultAmount);
    }

    function test_WithdrawAndRedeem() public {
        depositSome(defaultAmount);

        insurancePool.exit();

        skip(insurancePool.withdrawTime());

        uint256 shares = insurancePool.balanceOf(address(this));
        uint256 withdrawn = insurancePool.redeem(
            shares, 
            address(this), 
            address(this)
        );
        assertEq(withdrawn, defaultAmount);
        assertEq(insurancePool.balanceOf(address(this)), 0);
        assertEq(insurancePool.convertToAssets(shares), withdrawn);
    }

    function test_Exit() public {
        depositSome(defaultAmount);

        assertEq(insurancePool.withdrawQueue(address(this)), 0);
        insurancePool.exit();
        assertGt(insurancePool.withdrawQueue(address(this)), 0);

        skip(insurancePool.withdrawTime());
        insurancePool.redeem(
            insurancePool.balanceOf(address(this)) / 2,
            address(this),
            address(this)
        );
        assertEq(insurancePool.withdrawQueue(address(this)), 0);

        insurancePool.exit();
        skip(insurancePool.withdrawTime());
        insurancePool.withdraw(
            insurancePool.balanceOf(address(this)),
            address(this),
            address(this)
        );
        assertEq(insurancePool.withdrawQueue(address(this)), 0);
    }

    function test_CancelExit() public {
        depositSome(defaultAmount);

        assertEq(insurancePool.withdrawQueue(address(this)), 0);
        insurancePool.exit();
        assertGt(insurancePool.withdrawQueue(address(this)), 0);
        insurancePool.cancelExit();
        assertEq(insurancePool.withdrawQueue(address(this)), 0);

        // TODO: Should check rewards are claimable

    }

    function test_Rewards() public {
        depositSome(defaultAmount);

        bool isRegistered = emissionsController.isRegisteredReceiver(address(ipEmissionStream));
        uint256 id = emissionsController.receiverToId(address(ipEmissionStream));
        (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(id);
        console.log("Receiver:", receiver);
        console.log("Active:", active);
        console.log("Weight:", weight);
        console.log("id:", id);

        assertTrue(isRegistered);
        assertGt(id, 0);

        // TODO: Check rewards are minted
        skip(emissionsController.epochLength());

        skip(emissionsController.epochLength());
    }

    function depositSome(uint256 _amount) public {
        uint256 balance = insurancePool.balanceOf(address(this));
        insurancePool.deposit(_amount, address(this));
        assertEq(insurancePool.balanceOf(address(this)), balance + _amount);
    }
}
