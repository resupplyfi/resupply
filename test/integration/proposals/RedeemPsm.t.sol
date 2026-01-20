// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IPrismaFactory } from "src/interfaces/IPrismaFactory.sol";
import { RedeemPsm } from "script/proposals/RedeemPsm.s.sol";
import { ICrvUsdRedeemer } from "src/interfaces/prisma/ICrvUsdRedeemer.sol";
import { Protocol } from "src/Constants.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RedeemPsmTest is BaseProposalTest {
    RedeemPsm public script;
    uint256 public proposalId;

    uint256 public mkUsdTroveCountBefore;
    uint256 public ultraTroveCountBefore;

    function setUp() public override {
        super.setUp();

        script = new RedeemPsm();

        // Record trove manager counts before proposal
        mkUsdTroveCountBefore = script.factoryMkUsd().troveManagerCount();
        ultraTroveCountBefore = script.factoryUltra().troveManagerCount();

        proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_TroveManagersDeployedAndOperational() public {
        uint256 troveCountAfter = script.factoryMkUsd().troveManagerCount();
        assertEq(troveCountAfter, mkUsdTroveCountBefore + 1, "mkUSD TM not deployed");

        // Get the deployed proxy address
        address tmMkusd = script.factoryMkUsd().troveManagers(troveCountAfter - 1);
        assertTrue(tmMkusd != address(0), "mkUSD TM invalid");
        console.log("mkUSD tm deployed at:", tmMkusd);

        troveCountAfter = script.factoryUltra().troveManagerCount();
        assertEq(troveCountAfter, ultraTroveCountBefore + 1, "Ultra TM not deployed");

        // Get the deployed proxy address
        address tmUltra = script.factoryUltra().troveManagers(troveCountAfter - 1);
        assertTrue(tmUltra != address(0), "Ultra TM invalid");
        console.log("Ultra tm deployed at:", tmUltra);

        uint256 startBal = crvusd.balanceOf(Protocol.TREASURY);
        ICrvUsdRedeemer(tmMkusd).redeem();
        assertGt(crvusd.balanceOf(Protocol.TREASURY), startBal);

        startBal = crvusd.balanceOf(Protocol.TREASURY);
        ICrvUsdRedeemer(tmUltra).redeem();
        assertGt(crvusd.balanceOf(Protocol.TREASURY), startBal);
    }
}
