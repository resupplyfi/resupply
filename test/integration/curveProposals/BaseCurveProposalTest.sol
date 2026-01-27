// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet } from "src/Constants.sol";
import { Setup } from "test/integration/Setup.sol";
import { Test } from "forge-std/Test.sol";
import { ICurveVoting } from "src/interfaces/curve/ICurveVoting.sol";


contract BaseCurveProposalTest is Test, Setup {

    ICurveVoting public constant ownershipVoting = ICurveVoting(Mainnet.CURVE_OWNERSHIP_VOTING);
    ICurveVoting public constant parameterVoting = ICurveVoting(Mainnet.CURVE_PARAMETER_VOTING);
    uint256 constant VOTING_PERIOD = 8 days;

    function proposeOwnershipVote(bytes memory script, string memory metadata) public returns(uint256 proposalId){
        vm.prank(Mainnet.CONVEX_VOTEPROXY);
        proposalId = ownershipVoting.newVote(script, metadata, false, false);
    }

    function simulatePassingProposal(uint256 proposalId) public {
        address[] memory voters = new address[](3);
        voters[0] = Mainnet.CONVEX_VOTEPROXY;
        voters[1] = Mainnet.YEARN_VOTEPROXY;
        voters[2] = Mainnet.SD_VOTEPROXY;
        simulateYayVotes(proposalId, voters);
        executeOwnershipProposal(proposalId);
    }

    function simulateYayVotes(uint256 proposalId, address[] memory _voters) public {
        for (uint256 i = 0; i < _voters.length; i++) {
            if (!ownershipVoting.canVote(proposalId, _voters[i])) continue;
            vm.prank(_voters[i]);
            ownershipVoting.votePct(proposalId, 1e18,0, false);
        }
    }

    function executeOwnershipProposal(uint256 proposalId) public {
        (bool open, bool executed ,uint64 start, , ,,uint256 yea , uint256 nay , uint256 votingPower , bytes memory _script) = ownershipVoting.getVote(proposalId);
        if (executed) return;
        uint256 timeUntilExecutable = start + VOTING_PERIOD;
        timeUntilExecutable = timeUntilExecutable > block.timestamp ? timeUntilExecutable - block.timestamp : 0;
        if (timeUntilExecutable > 0) skip(timeUntilExecutable);
        ownershipVoting.executeVote(proposalId);
    }

    function getWhaleVoters() public pure returns (address[] memory) {
        address[] memory voters = new address[](3);
        voters[0] = Mainnet.CONVEX_VOTEPROXY;
        voters[1] = Mainnet.YEARN_VOTEPROXY;
        voters[2] = Mainnet.SD_VOTEPROXY;
        return voters;
    }

    function dependsOnProposal(uint256 proposalId) public {
        (bool open, bool executed ,uint64 start, , ,,uint256 yea , uint256 nay , uint256 votingPower , bytes memory _script) = ownershipVoting.getVote(proposalId);
        if (!open) {
            if (!executed) executeOwnershipProposal(proposalId);
            return;
        }
        simulatePassingProposal(proposalId);
    }

    function isExecuted(uint256 proposalId) public returns (bool) {
        if (proposalId == 0) return false;
        (,bool executed,,,,,, , ,) = ownershipVoting.getVote(proposalId);
        return executed;
    }
}