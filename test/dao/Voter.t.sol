pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { GovStaker } from "../../src/dao/staking/GovStaker.sol";
import { GovStakerEscrow } from "../../src/dao/staking/GovStakerEscrow.sol";
import { MockToken } from "../mocks/MockToken.sol";
import { Setup } from "./utils/Setup.sol";
import { MockPair } from "../mocks/MockPair.sol";
import { Voter } from "../../src/dao/Voter.sol";
import { ICore } from "../../src/interfaces/ICore.sol";

contract VoterTest is Setup {
    MockPair pair;
    function setUp() public override {
        super.setUp();

        // Create a mock protocol contract for us to test with
        pair = new MockPair(address(core));

        // Transfer ownership of the core contract to the voter contract
        vm.prank(address(core));
        core.transferVoter(address(voter));
        vm.prank(address(voter));
        core.acceptTransferVoter();

        // Give user1 some stake so they can create a proposal + vote.
        vm.prank(user1);
        staker.stake(user1, 100e18);
        skip(staker.epochLength() * 2); // We skip 2, so that the stake can be registered (first epoch) and finalized (second epoch).
        
    }

    function test_createProposal() public {
        uint256 proposalId = 69; // Set to a non-zero number to start with
        uint256 epoch = voter.getEpoch()-1; // Prior epoch to be used for voting

        uint256 quorumWeight = uint40(staker.getTotalWeightAt(epoch) / 10 ** voter.TOKEN_DECIMALS() * voter.passingPct() / 10_000);
        vm.expectEmit(true, true, false, true);
        emit Voter.ProposalCreated(
            user1, 
            0, 
            buildProposalData(5), 
            voter.getEpoch()-1, 
            quorumWeight
        );
        vm.prank(user1);
        proposalId = voter.createNewProposal(
            user1,
            buildProposalData(5)
        );

        assertEq(pair.value(), 0);
        assertEq(voter.getProposalCount(), 1);
        assertEq(proposalId, 0);
    }

    function test_createProposalFor() public {
        uint256 proposalId = 69; // Set to a non-zero number to start with

        vm.expectRevert("!CallerOrDelegated");
        vm.prank(user2);
        proposalId = voter.createNewProposal(
            user1,
            buildProposalData(5)
        );
        
        vm.prank(user1);
        voter.setDelegateApproval(user2, true);
        assertEq(voter.isApprovedDelegate(user1, user2), true);

        vm.prank(user2);
        proposalId = voter.createNewProposal(
            user1,
            buildProposalData(5)
        );
        assertEq(pair.value(), 0);
        assertEq(voter.getProposalCount(), 1);
        assertEq(proposalId, 0);
        assertEq(voter.canExecute(proposalId), false);
    }

    function test_voteForProposal() public {
        uint256 proposalId = 69; // Set to a non-zero number to start with
        uint256 epoch = voter.getEpoch()-1; // Prior epoch to be used for voting
        vm.prank(user1);
        proposalId = voter.createNewProposal(
            user1,
            buildProposalData(5)
        );

        vm.prank(user1);

        voter.voteForProposal(user1, proposalId);

        assertEq(voter.quorumReached(proposalId), true);
        assertEq(voter.canExecute(proposalId), false);
        skip(voter.VOTING_PERIOD());
        assertEq(voter.canExecute(proposalId), false);
        skip(voter.EXECUTION_DELAY());

        (
            uint256 _epoch,
            uint256 _createdAt,
            ,
            uint256 _weightYes,
            uint256 _weightNo,
            bool _processed,
            bool _executable,
        ) = voter.getProposalData(proposalId);
        assertEq(epoch, _epoch);
        assertGt(_createdAt, 0);
        assertGt(_weightYes, 0);
        assertEq(_weightNo, 0);
        assertEq(_processed, false);
        assertEq(_executable, true);
        assertEq(voter.canExecute(proposalId), true);

        vm.expectEmit(true, false, false, true);
        emit Voter.ProposalExecuted(proposalId);
        voter.executeProposal(proposalId); //  Permissionless, no prank needed
        assertEq(pair.value(), 5);
    }

    function test_transferVoter() public {
        vm.prank(address(core));
        core.transferVoter(address(user2));
        assertEq(core.voter(), address(voter)); // Should not be transferred yet

        vm.prank(address(user2));
        core.acceptTransferVoter();
        assertEq(core.voter(), address(user2));
    }

    function test_cancelProposal() public {
        bool _processed;
        vm.prank(user1);
        uint256 propId = voter.createNewProposal(user1, buildProposalData(5));
        (,,,,,_processed,,) = voter.getProposalData(propId);
        assertEq(_processed, false);

        vm.prank(address(core));
        voter.cancelProposal(propId);
        (,,,,,_processed,,) = voter.getProposalData(propId);
        assertEq(_processed, true);
    }

    function test_CannotCancelProposalWithCancelerPayload() public {
        uint256 propId = createProposalDataWithCanceler();
        vm.prank(address(core));
        vm.expectRevert("Contains canceler payload");
        voter.cancelProposal(propId);
    }

    function buildProposalData(uint256 _value) public view returns (Voter.Action[] memory) {
        Voter.Action[] memory payload = new Voter.Action[](1);
        payload[0] = Voter.Action({
            target: address(pair),
            data: abi.encodeWithSelector(pair.setValue.selector, _value)
        });
        return payload;
    }

    function createProposalDataWithCanceler() public returns (uint256) {
        Voter.Action[] memory payload = new Voter.Action[](1);
        payload[0] = Voter.Action({
            target: address(core),
            data: abi.encodeWithSelector(
                core.setOperatorPermissions.selector, 
                address(0),
                address(voter), 
                ICore.cancelProposal.selector, 
                true,
                address(0)
            )
        });
        vm.prank(user1);
        return voter.createNewProposal(user1, payload);
    }
}
