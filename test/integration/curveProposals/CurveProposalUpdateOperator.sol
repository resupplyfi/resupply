// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "forge-std/console.sol";
import { BaseCurveProposalTest } from "test/integration/curveProposals/BaseCurveProposalTest.sol";
import { ICurveVoting } from "src/interfaces/curve/ICurveVoting.sol";
import { CurveProposalReplaceOperator } from "script/proposals/curve/CurveProposalReplaceOperator.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { CurveLendOperator } from "src/dao/CurveLendOperator.sol";
import { CurveLendMinterFactory } from "src/dao/CurveLendMinterFactory.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';

contract CurveProposalUpdateOperator is BaseCurveProposalTest {
    CurveProposalReplaceOperator proposalScript;

    IERC20 public crvusd = IERC20(Mainnet.CRVUSD_ERC20);

    CurveLendMinterFactory public factory;
    IERC20 public market;

    function setUp() public override {
        super.setUp();
        proposalScript = new CurveProposalReplaceOperator();
        market = IERC20(Mainnet.CURVELEND_SREUSD_CRVUSD);

        proposalScript.setDeployAddresses(address(market));

        factory = CurveLendMinterFactory(Mainnet.CURVE_LENDING_FACTORY);

        bytes memory script = proposalScript.buildProposalScript();

        string memory metadata = "Update lending operator implementation. Increase lending to sreusd market to 10m.";
        console.log("meta: ", metadata);
        uint256 proposalId = proposeOwnershipVote(script, metadata);
        console.log("crv supply balance: ", crvusd.totalSupply() );
        simulatePassingOwnershipVote(proposalId);
        executeOwnershipProposal(proposalId);
    }

    function test_mintAndSupply() public {
        console.log("factory address: ", address(factory));
        console.log("factory crvusd balance: ", crvusd.balanceOf(address(factory)) );
        console.log("crv supply balance: ", crvusd.totalSupply() );

        CurveLendOperator oldoperator = CurveLendOperator(0x6119e210E00d4BE2Df1B240D82B1c3DECEdbBBf0);
        address operator = factory.markets(address(market));
        console.log("supplied shares on operator: ", market.balanceOf(operator));
        console.log("supplied shares on oldoperator: ", market.balanceOf(address(oldoperator)));

        console.log("withdraw profit...");
        oldoperator.withdraw_profit();
        console.log("supplied shares on oldoperator: ", market.balanceOf(address(oldoperator)));
    }


}