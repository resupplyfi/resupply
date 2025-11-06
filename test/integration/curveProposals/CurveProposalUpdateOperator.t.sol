// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "forge-std/console.sol";
import { BaseCurveProposalTest } from "test/integration/curveProposals/BaseCurveProposalTest.sol";
import { CurveProposalReplaceOperator } from "script/proposals/curve/CurveProposalReplaceOperator.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { CurveLendOperator } from "src/dao/CurveLendOperator.sol";
import { CurveLendMinterFactory } from "src/dao/CurveLendMinterFactory.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';
import { ICurveLendController } from 'src/interfaces/curve/ICurveLendController.sol';
import { ICurveLendingVault } from 'src/interfaces/curve/ICurveLendingVault.sol';
import { ICurveLendOperator } from 'src/interfaces/curve/ICurveLendOperator.sol';

contract CurveProposalUpdateOperator is BaseCurveProposalTest {
    CurveProposalReplaceOperator proposalScript;
    ICurveLendOperator oldoperator;
    CurveLendOperator operator;
    CurveLendMinterFactory public factory;
    address public feeReceiver;
    IERC20 public market;

    function setUp() public override {
        super.setUp();
        dependsOnProposal(1252); // https://www.curve.finance/dao/ethereum/proposals/1252-ownership
        proposalScript = new CurveProposalReplaceOperator();
        market = IERC20(Mainnet.CURVELEND_SREUSD_CRVUSD);

        CurveLendOperator lenderImpl = new CurveLendOperator();

        proposalScript.setDeployAddresses(address(market), address(lenderImpl));

        factory = CurveLendMinterFactory(Mainnet.CURVE_LENDING_FACTORY);

        bytes memory script = proposalScript.buildProposalScript();

        string memory metadata = "Update lending operator implementation. Increase lending to sreusd market to 10m.";
        console.log("meta: ", metadata);
        uint256 proposalId = proposeOwnershipVote(script, metadata);
        console.log("crvusd supply balance before: ", crvusd.totalSupply() );
        simulatePassingProposal(proposalId);
        feeReceiver = factory.fee_receiver();
        oldoperator = ICurveLendOperator(proposalScript.OLD_OPERATOR());
        operator = CurveLendOperator(factory.markets(address(market)));
    }

    function test_mintAndSupply() public {
        console.log("factory address: ", address(factory));
        console.log("factory crvusd balance: ", crvusd.balanceOf(address(factory)) );
        console.log("crvusd supply balance: ", crvusd.totalSupply() );
        console.log("supplied shares on operator: ", market.balanceOf(address(operator)));
        console.log("supplied shares on oldoperator: ", market.balanceOf(address(oldoperator)));
        console.log("older operator mintLimit: ", oldoperator.mintLimit());
        console.log("older operator mintedAmount: ", oldoperator.mintedAmount());


        console.log("withdraw profit on old operator...");
        oldoperator.withdraw_profit();
        console.log("supplied shares on oldoperator: ", market.balanceOf(address(oldoperator)));

        skip(5 days);
        console.log("advance time...");
        console.log("supplied shares on operator: ", market.balanceOf(address(operator)));
        console.log("profits: ", operator.profit());
        operator.withdraw_profit();
        console.log("withdraw profit...");
        console.log("supplied shares on operator: ", market.balanceOf(address(operator)));
    }

    // function test_ProfitIsWithdrawnFromOldOperator() public {
    //     uint256 beforeBalance = crvusd.balanceOf(feeReceiver);
    //     oldoperator.withdraw_profit();
    //     uint256 afterBalance = crvusd.balanceOf(feeReceiver);
    //     assertEq(afterBalance, beforeBalance, "should have no profit after proposal");
    // }

    function test_CanWithdrawProfitWithFullUtilization() public {
        ICurveLendingVault vault = ICurveLendingVault(address(market));
        IERC20 collateral = IERC20(vault.collateral_token());
        ICurveLendController controller = ICurveLendController(vault.controller());
        deal(address(collateral), address(this), 100_000_000e18);
        collateral.approve(address(controller), type(uint256).max);
        crvusd.approve(address(vault), type(uint256).max);
        
        uint256 availableDebt = crvusd.balanceOf(address(controller));
        controller.create_loan(100_000_000e18, availableDebt, 10, address(this));
        assertEq(crvusd.balanceOf(address(controller)), 0, "not all liquidity was used");

        skip(1 days);
        CurveLendOperator operator = CurveLendOperator(factory.markets(address(market)));
        uint256 profit = operator.profit();
        assertGt(profit, 0, "no profit available");

        address feeReceiver = factory.fee_receiver();
        uint256 beforeBalance = crvusd.balanceOf(feeReceiver);

        // Call to withdraw profit should revert when no liquidity is available.
        vm.expectRevert();
        operator.withdraw_profit();

        // Deposit profit to operator to make it available as profit to be withdrawn.
        vault.deposit(profit, address(this));
        profit = operator.withdraw_profit();
        uint256 gain = crvusd.balanceOf(feeReceiver) - beforeBalance;
        assertGt(gain, 0, "no profit was received");
        assertEq(profit, gain, "profit should be equal to gain");
    }
}