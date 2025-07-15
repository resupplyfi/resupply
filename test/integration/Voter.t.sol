pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { GovStaker } from "src/dao/staking/GovStaker.sol";
import { GovStakerEscrow } from "src/dao/staking/GovStakerEscrow.sol";
import { MockToken } from "test/mocks/MockToken.sol";
import { Setup } from "test/integration/Setup.sol";
import { MockPair } from "test/mocks/MockPair.sol";
import { Voter } from "src/dao/Voter.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IGovStaker } from "src/interfaces/IGovStaker.sol";

contract VoterTest is Setup {
    MockPair pair;
    uint256 public MAX_PCT;
    address user1 = address(permaStaker1);
    address user2 = address(permaStaker2);
    address newUser = address(123);
    function setUp() public override {
        super.setUp();
        user1 = address(permaStaker1);
        
        MAX_PCT = voter.MAX_PCT();

        // Create a mock protocol contract for us to test with
        pair = new MockPair(address(core));

        // Transfer ownership of the core contract to the new voter contract
        address voterAddress = address(new Voter(address(core), address(staker), 100, 3000, 0));
        voter = IVoter(voterAddress);
        vm.prank(address(core));
        core.setVoter(voterAddress);
    }

    function test_createProposal() public {
        uint256 proposalId;
        uint256 epoch = voter.getEpoch(); // Current epoch is used for voting

        // String size: 408 bytes
        string memory longInvalidDescription = "here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats.here is a very long string that repeats.";
        // String size: 368 bytes
        string memory longValidDescrition = "here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats. here is a very long string that repeats.";
        uint256 quorumWeight = uint40(staker.getTotalWeightAt(epoch) / 10 ** voter.TOKEN_DECIMALS() * voter.quorumPct() / 10_000);
        vm.expectRevert("Description too long");
        vm.prank(user1);
        proposalId = voter.createNewProposal(
            user1,
            buildProposalData(5),
            longInvalidDescription
        );

        vm.expectEmit(true, true, false, true);
        emit IVoter.ProposalCreated(
            user1, 
            proposalId, 
            buildProposalData(5), 
            voter.getEpoch(), 
            quorumWeight
        );
        vm.prank(user1);
        proposalId = voter.createNewProposal(
            user1,
            buildProposalData(5),
            longValidDescrition
        );

        assertEq(pair.value(), 0);
    }

    function test_createProposalFor() public {
        uint256 proposalId;

        vm.expectRevert("!CallerOrDelegated");
        vm.prank(user2);
        proposalId = voter.createNewProposal(
            user1,
            buildProposalData(5),
            "Test proposal"
        );
        
        vm.prank(user1);
        voter.setDelegateApproval(user2, true);
        assertEq(voter.isApprovedDelegate(user1, user2), true);

        vm.prank(user2);
        proposalId = voter.createNewProposal(
            user1,
            buildProposalData(5),
            "Test proposal"
        );
        assertEq(pair.value(), 0);
        assertEq(voter.canExecute(proposalId), false);
    }

    function test_CannotReplayProposal() public {
        uint256 propId = createSimpleProposal();
        passProposal(propId);
        assertEq(voter.canExecute(propId), true);
        voter.executeProposal(propId);
        assertEq(voter.canExecute(propId), false);
    }

    function test_voteForProposal() public {
        uint256 proposalId = 69; // Set to a non-zero number to start with
        uint256 epoch = voter.getEpoch(); // Current epoch is used for voting
        vm.prank(user1);
        proposalId = voter.createNewProposal(
            user1,
            buildProposalData(5),
            "Test proposal"
        );

        vm.startPrank(user1);
        vm.expectRevert("Sum of pcts must equal MAX_PCT");
        voter.voteForProposal(user1, proposalId, MAX_PCT+1, MAX_PCT);
        vm.expectRevert("Sum of pcts must equal MAX_PCT");
        voter.voteForProposal(user1, proposalId, MAX_PCT, MAX_PCT+1);
        vm.expectRevert("Sum of pcts must equal MAX_PCT");
        voter.voteForProposal(user1, proposalId, MAX_PCT, 1);
        vm.expectRevert("Sum of pcts must equal MAX_PCT");
        voter.voteForProposal(user1, proposalId, 1, 1);
        voter.voteForProposal(user1, proposalId, MAX_PCT, 0);
        vm.expectRevert("Already voted");
        voter.voteForProposal(user1, proposalId);
        vm.stopPrank();
        
        vm.prank(user2);
        voter.voteForProposal(user2, proposalId);

        assertEq(voter.quorumReached(proposalId), true);
        assertEq(voter.canExecute(proposalId), false);
        vm.warp(voter.getProposalData(proposalId).endsAt);
        assertEq(voter.canExecute(proposalId), false);
        vm.expectRevert("Proposal cannot be executed");
        voter.executeProposal(proposalId);
        vm.warp(voter.getProposalData(proposalId).executeAfter);

        IVoter.ProposalFullData memory proposal = voter.getProposalData(proposalId);
        assertEq(epoch, proposal.epoch);
        assertGt(proposal.createdAt, 0);
        assertGt(proposal.weightYes, 0);
        assertEq(proposal.weightNo, 0);
        assertEq(proposal.processed, false);
        assertEq(proposal.executable, true);
        assertEq(voter.canExecute(proposalId), true);

        vm.expectEmit(true, false, false, true);
        emit Voter.ProposalExecuted(proposalId);
        voter.executeProposal(proposalId); //  Permissionless, no prank needed
        assertEq(pair.value(), 5);
    }

    function test_SetVoter() public {
        vm.prank(address(core));
        core.setVoter(address(user2));
        assertEq(core.voter(), address(user2));
    }

    function test_cancelProposal() public {
        bool _processed;
        vm.prank(user1);
        uint256 propId = voter.createNewProposal(user1, buildProposalData(5), "Test proposal");
        IVoter.ProposalFullData memory proposal = voter.getProposalData(propId);
        assertEq(proposal.processed, false);

        vm.prank(address(core));
        voter.cancelProposal(propId);
        proposal = voter.getProposalData(propId);
        assertEq(proposal.processed, true);
    }

    function test_CannotCancelProposalWithCancelerPayload() public {
        uint256 propId = createProposalDataWithCanceler();
        vm.prank(address(core));
        vm.expectRevert("Contains canceler payload");
        voter.cancelProposal(propId);
    }

    function test_CannotCreateMultiActionProposalWithCanceler() public {
        vm.expectRevert("Payload length not 1");
        createProposalDataWithCancelerAsNonFirstAction();
    }

    function test_CannotCancelProposalWithCancelerPayloadAndTargetIsZeroAddress() public {
        uint256 propId = createProposalDataWithCancelerAndTargetIsZeroAddress();
        vm.prank(address(core));
        vm.expectRevert("Contains canceler payload");
        voter.cancelProposal(propId);
    }

    function test_updateProposalDescription() public {
        uint256 propId = createSimpleProposal();
        vm.prank(user1);
        vm.expectRevert("!core");
        voter.updateProposalDescription(propId, "New description");
        vm.prank(address(core));
        voter.updateProposalDescription(propId, "New description!");
        IVoter.ProposalFullData memory proposal = voter.getProposalData(propId);
        assertEq(proposal.description, "New description!");
    }

    function buildProposalData(uint256 _value) public view returns (IVoter.Action[] memory) {
        IVoter.Action[] memory payload = new IVoter.Action[](1);
        payload[0] = IVoter.Action({
            target: address(pair),
            data: abi.encodeWithSelector(pair.setValue.selector, _value)
        });
        return payload;
    }

    function createProposalDataWithCanceler() public returns (uint256) {
        IVoter.Action[] memory payload = new IVoter.Action[](1);
        payload[0] = IVoter.Action({
            target: address(core),
            data: abi.encodeWithSelector(
                core.setOperatorPermissions.selector, 
                address(0),
                address(voter), 
                Voter.cancelProposal.selector, 
                true,
                address(0)
            )
        });
        vm.prank(user1);
        return voter.createNewProposal(user1, payload, "Test proposal");
    }

    function createProposalDataWithCancelerAsNonFirstAction() public returns (uint256) {
        IVoter.Action[] memory payload = new IVoter.Action[](2);
        // Dummy action
        payload[0] = IVoter.Action({
            target: address(pair),
            data: abi.encodeWithSelector(pair.setValue.selector, 0)
        });
        // Canceler action
        payload[1] = IVoter.Action({
            target: address(core),
            data: abi.encodeWithSelector(
                core.setOperatorPermissions.selector, 
                address(0),
                address(voter), 
                Voter.cancelProposal.selector, 
                true,
                address(0)
            )
        });
        vm.prank(user1);
        return voter.createNewProposal(user1, payload, "Test proposal");
    }

    function createProposalDataWithCancelerAndTargetIsZeroAddress() public returns (uint256) {
        IVoter.Action[] memory payload = new IVoter.Action[](1);
        payload[0] = IVoter.Action({
            target: address(core),
            data: abi.encodeWithSelector(
                core.setOperatorPermissions.selector, 
                address(0),
                address(0), 
                IVoter.cancelProposal.selector, 
                true,
                address(0)
            )
        });
        vm.prank(user1);
        return voter.createNewProposal(user1, payload, "Test proposal");
    }

    function test_setMinCreateProposalPct() public {
        vm.expectRevert("!core");
        voter.setMinCreateProposalPct(5000);

        vm.startPrank(address(core));
        voter.setMinCreateProposalPct(5000);

        vm.expectRevert("Too low");
        voter.setMinCreateProposalPct(0);

        vm.expectRevert("Invalid value");
        voter.setMinCreateProposalPct(MAX_PCT+1);
        vm.stopPrank();
    }

    function test_SetQuorumPct() public {
        vm.expectRevert("!core");
        voter.setQuorumPct(5000);

        vm.startPrank(address(core));
        voter.setQuorumPct(5000);

        vm.expectRevert("Too low");
        voter.setQuorumPct(0);

        vm.expectRevert("Invalid value");
        voter.setQuorumPct(MAX_PCT+1);
        vm.stopPrank();
    }

    function createSimpleProposal() public returns (uint256) {
        IVoter.Action[] memory payload = new IVoter.Action[](1);
        payload[0] = IVoter.Action({
            target: address(pair),
            data: abi.encodeWithSelector(
                pair.setValue.selector, 
                5
            )
        });
        vm.prank(user1);
        return voter.createNewProposal(user1, payload, "Test proposal");
    }

    function passProposal(uint256 propId) public {
        vm.prank(user1);
        voter.voteForProposal(user1, propId);
        vm.prank(user2);
        voter.voteForProposal(user2, propId);
        vm.warp(voter.getProposalData(propId).executeAfter);
    }
}