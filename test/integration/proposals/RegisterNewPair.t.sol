// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { RegisterNewPair } from "script/proposals/RegisterNewPair.s.sol";

contract RegisterNewPairTest is BaseProposalTest {
    RegisterNewPair public script;
    uint256 public proposalId;
    address public pairAddress;

    function setUp() public override {
        super.setUp();
        console.log("Running from block:", block.number);
        //if(isProposalProcessed(10)) return;
        script = new RegisterNewPair();
        pairAddress = script.PAIR_ADDRESS();
        printActions();

        proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }
    
    function printActions() public {
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        for (uint256 i = 0; i < actions.length; i++) {
            console.log("Action", i+1);
            console.log("Target:", actions[i].target);
            console.logBytes(actions[i].data);
            console.log("--------------------------------");
        }
    }
    
    function test_PairDeploymentAddressPrediction() public {
        assertNotEq(pairAddress, address(0), "Address should not be zero");
        assertGt(address(pairAddress).code.length, 0, "Address should have code");
        assertGt(registry.getAllPairAddresses().length, pairs.length, "Registry should have new pair");
    }
    
    function test_RampBorrowLimitCalldata() public {
        address testPair = pairAddress;
        uint256 newBorrowLimit = 100_000_000e18;
        uint256 endTime = block.timestamp + 20 days;
        
        bytes memory rampBorrowLimitData = script.getRampBorrowLimitCallData(
            testPair, 
            newBorrowLimit, 
            endTime
        );
        
        // Verify the calldata is properly encoded
        assertGt(rampBorrowLimitData.length, 0, "Ramp borrow limit calldata should not be empty");
        
        console.log("Ramp borrow limit calldata:");
        console.logBytes(rampBorrowLimitData);
    }
}