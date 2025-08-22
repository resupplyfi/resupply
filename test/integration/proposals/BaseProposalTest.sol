// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { Test } from "forge-std/Test.sol";
import { Setup } from "test/integration/Setup.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";

contract BaseProposalTest is Test, Setup {

    address[] public pairs;

    constructor() {
        pairs = registry.getAllPairAddresses();
    }

    function createProposal(IVoter.Action[] memory actions) public returns (uint256) {
        vm.prank(Protocol.PERMA_STAKER_CONVEX);
        return voter.createNewProposal(Protocol.PERMA_STAKER_CONVEX, actions, "Test proposal");
    }

    function simulatePassingVote(uint256 proposalId) public {
        vm.prank(Protocol.PERMA_STAKER_CONVEX);
        voter.voteForProposal(Protocol.PERMA_STAKER_CONVEX, proposalId);
        vm.prank(Protocol.PERMA_STAKER_YEARN);
        voter.voteForProposal(Protocol.PERMA_STAKER_YEARN, proposalId);
        skip(voter.votingPeriod());
    }

    function executeProposal(uint256 proposalId) public {
        skip(voter.executionDelay());
        voter.executeProposal(proposalId);
    }
}