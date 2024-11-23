pragma solidity ^0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/Setup.sol";
import { SimpleReceiverFactory } from "src/dao/emissions/receivers/SimpleReceiverFactory.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { GovToken } from "src/dao/GovToken.sol";
import { EmissionsController } from "src/dao/emissions/EmissionsController.sol";

contract InsurancePoolTest is Setup {
    function setUp() public override {
        super.setUp();

        stablecoin.approve(address(insurancePool), type(uint256).max);
        deal(address(stablecoin), address(this), 10_000e18);
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

    function test_DepositAndMint() public {

    }

    function test_WithdrawAndRedeem() public {

    }

    function test_BurnAssets() public {

    }

    function test_Exit() public {

    }

    function test_CancelExit() public {

    }

    function test_Rewards() public {

    }

    function depositSome(uint256 _amount) public {
        uint256 balance = insurancePool.balanceOf(address(this));
        insurancePool.deposit(_amount, address(this));
        assertEq(insurancePool.balanceOf(address(this)), balance + _amount);
    }
}
