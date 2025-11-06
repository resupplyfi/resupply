// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { Protocol, Mainnet } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { SetRedemptionHandler } from "script/proposals/SetRedemptionHandler.s.sol";

contract SetRedemptionHandlerTest is BaseProposalTest {
    uint256 public constant PROP_ID = 10;
    SetRedemptionHandler public script;
    uint256 public proposalId;
    address public redemptionHandlerAddress;
    IRedemptionHandler newRedemptionHandler = IRedemptionHandler(Protocol.REDEMPTION_HANDLER);

    function setUp() public override {
        super.setUp();
        console.log("Running from block:", block.number);
        if(isProposalProcessed(PROP_ID)) return;
        address oldRedemptionHandler = registry.getAddress("REDEMPTION_HANDLER");        
        assertNotEq(Protocol.REDEMPTION_HANDLER, oldRedemptionHandler, "Redemption handler should be deployed");
        assertEq(address(newRedemptionHandler), Protocol.REDEMPTION_HANDLER, "Redemption handler should be deployed");
        script = new SetRedemptionHandler();

        proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }
    
    function test_NewRedemptionHandlerAddress() public {
        address newRedemptionHandler = registry.getAddress("REDEMPTION_HANDLER");
        assertEq(newRedemptionHandler, registry.redemptionHandler(), "Wrong address");
        assertEq(Protocol.REDEMPTION_HANDLER, newRedemptionHandler, "Wrong address");
    }

    function test_NewWeightLimit() public {
        if(isProposalProcessed(PROP_ID)) return;
        assertEq(script.WEIGHT_LIMIT(), newRedemptionHandler.overWeight(), "Wrong weight limit");
    }
}