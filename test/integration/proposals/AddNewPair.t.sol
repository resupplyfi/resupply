// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { Protocol, Mainnet } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { AddNewPair } from "script/proposals/AddNewPair.s.sol";

contract AddNewPairTest is BaseProposalTest {
    AddNewPair public script;
    uint256 public proposalId;
    address public predictedAddress;

    function setUp() public override {
        super.setUp();
        console.log("Running from block:", block.number);
        //if(isProposalProcessed(10)) return;
        deal(Mainnet.CRVUSD_ERC20, Protocol.PAIR_DEPLOYER_V2, 1_000e18);
        deal(Mainnet.FRXUSD_ERC20, Protocol.PAIR_DEPLOYER_V2, 1_000e18);
        script = new AddNewPair();
        printActions();
        
        address c = deployer.contractAddress1();
        console.log("contract address 1:", c);
        require(c.code.length > 0, "contract address 1 is not set");
        c = deployer.contractAddress2();
        console.log("contract address 2:", c);
        require(c.code.length > 0, "contract address 2 is not set");

        (predictedAddress, ) = script.getPairDeploymentAddressAndCallData(
            script.PROTOCOL_ID(), // protocol id
            script.COLLATERAL(), // collateral
            script.STAKING(), // staking
            script.STAKING_ID() // staking id
        );

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
        assertNotEq(predictedAddress, address(0), "Predicted address should not be zero");
        assertGt(address(predictedAddress).code.length, 0, "Predicted address should have code");
        assertGt(registry.getAllPairAddresses().length, pairs.length, "Registry should have new pair");
    }
    
    function test_RampBorrowLimitCalldata() public {
        address testPair = address(0x1234567890123456789012345678901234567890);
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