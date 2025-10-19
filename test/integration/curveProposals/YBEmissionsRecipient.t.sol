// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "forge-std/console.sol";
import { BaseCurveProposalTest } from "test/integration/curveProposals/BaseCurveProposalTest.sol";
import { ICurveVoting } from "src/interfaces/curve/ICurveVoting.sol";
import { YBEmissionsRecipient } from "script/proposals/curve/YBEmissionsRecipient.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IInflationaryVest } from 'src/interfaces/curve/IInflationaryVest.sol';

contract YBEmissionsRecipientTest is BaseCurveProposalTest {
    YBEmissionsRecipient proposalScript;

    uint256 public voteLength;

    function setUp() public override {
        super.setUp();
        proposalScript = new YBEmissionsRecipient();

        voteLength = ownershipVoting.votesLength();
        bytes memory script = proposalScript.buildProposalScript();

        uint256 proposalId = proposeOwnershipVote(script, "Set the recipient of the inflationary vest to 0x0997f89c451124EadF00f87DE77924D77A38419a");
        simulatePassingOwnershipVote(proposalId);
        executeOwnershipProposal(proposalId);
    }

    function test_recipientSet() public view {
        address targetRecipient = proposalScript.recipient();
        address recipient = IInflationaryVest(proposalScript.inflationaryVest()).recipient();
        console.log("recipient: ", recipient);
        assertEq(recipient, targetRecipient);
    }

    function test_voteLength() public view {
        assertEq(ownershipVoting.votesLength(), voteLength + 1);
    }
}