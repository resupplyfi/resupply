// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "forge-std/console.sol";
import { BaseCurveProposalTest } from "test/integration/curveProposals/BaseCurveProposalTest.sol";
import { ICurveVoting } from "src/interfaces/curve/ICurveVoting.sol";
import { CurveProposalMint } from "script/proposals/CurveProposalMint.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { CurveLendOperator } from "src/dao/CurveLendOperator.sol";
import { CurveLendMinterFactory } from "src/dao/CurveLendMinterFactory.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';

contract CurveProposalMintTest is BaseCurveProposalTest {
    CurveProposalMint proposalScript;

    IERC20 public crvusd = IERC20(Mainnet.CRVUSD_ERC20);

    CurveLendMinterFactory public factory;
    IERC20 public market;

    function setUp() public override {
        super.setUp();

        //deploy implementation and factory
        CurveLendOperator lenderImpl = new CurveLendOperator();

        ICrvusdController crvusdController = ICrvusdController(Mainnet.CURVE_CRVUSD_CONTROLLER);
        address feeReceiver = crvusdController.fee_receiver();

        factory = new CurveLendMinterFactory(
            Mainnet.CURVE_OWNERSHIP_AGENT,
            address(crvusdController),
            feeReceiver,
            address(lenderImpl)
        );

        market = IERC20(Mainnet.CURVELEND_SREUSD_CRVUSD);

        proposalScript = new CurveProposalMint();

        proposalScript.setDeployAddresses(address(factory), address(market));

        bytes memory script = proposalScript.buildProposalScript();

        uint256 proposalId = proposeOwnershipVote(script, "Test Proposal");
        console.log("crv supply balance: ", crvusd.totalSupply() );
        simulatePassingOwnershipVote(proposalId);
        executeOwnershipProposal(proposalId);
    }

    function test_mintAndSupply() public view {
        console.log("factory address: ", address(factory));
        console.log("factory crvusd balance: ", crvusd.balanceOf(address(factory)) );
        console.log("crv supply balance: ", crvusd.totalSupply() );

        address operator = factory.markets(address(market));
        console.log("supplied shares on operator: ", market.balanceOf(operator));
    }


}