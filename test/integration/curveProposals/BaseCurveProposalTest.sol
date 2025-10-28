// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { Protocol, Mainnet } from "src/Constants.sol";
import { Setup } from "test/integration/Setup.sol";
import { Test } from "forge-std/Test.sol";
import { Setup } from "test/integration/Setup.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ICurveVoting } from "src/interfaces/curve/ICurveVoting.sol";


contract BaseCurveProposalTest is Test, Setup {

    ICurveVoting public constant ownershipVoting = ICurveVoting(Mainnet.CURVE_OWNERSHIP_VOTING);
    ICurveVoting public constant parameterVoting = ICurveVoting(Mainnet.CURVE_PARAMETER_VOTING);
    uint256 constant VOTING_PERIOD = 8 days;

    function proposeOwnershipVote(bytes memory script, string memory metadata) public returns(uint256 proposalId){
        vm.prank(Mainnet.CONVEX_VOTEPROXY);
        proposalId = ownershipVoting.newVote(script, metadata, false, false);
    }

    function simulatePassingOwnershipVote(uint256 proposalId) public {
        vm.prank(Mainnet.CONVEX_VOTEPROXY);
        ownershipVoting.votePct(proposalId, 1e18,0, false);
        skip(VOTING_PERIOD);

        // (bool open, bool executed ,uint64 start, , ,,uint256 yea , uint256 nay , uint256 votingPower , bytes memory _script) = ownershipVoting.getVote(proposalId);
        // console.log("open: ", open);
        // console.log("executed: ", executed);
        // console.log("start: ", start);
        // console.log("yea: ", yea);
        // console.log("nay: ", nay);
        // console.log("votingPower: ", votingPower);
        // console.logBytes(_script);
        // console.log("can execute? ", ownershipVoting.canExecute(proposalId));
    }

    function executeOwnershipProposal(uint256 proposalId) public {
        ownershipVoting.executeVote(proposalId);
        (bool open, bool executed ,uint64 start, , ,,uint256 yea , uint256 nay , uint256 votingPower , bytes memory _script) = ownershipVoting.getVote(proposalId);
        console.log("-------- executed proposal -----------");
        // console.log("open: ", open);
        // console.log("executed: ", executed);
        // console.log("start: ", start);
        // console.log("yea: ", yea);
        // console.log("nay: ", nay);
        // console.log("votingPower: ", votingPower);
        // console.logBytes(_script);
        // console.log("can execute? ", ownershipVoting.canExecute(proposalId));
    }
}