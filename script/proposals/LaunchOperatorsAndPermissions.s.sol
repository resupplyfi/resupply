// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { console } from "lib/forge-std/src/console.sol";
import { OperatorMigrationPermissionsBuilder } from "script/proposals/data/OperatorMigrationPermissionsBuilder.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract LaunchOperatorsAndPermissions is BaseAction, BaseProposal {
    function run() public isBatch(deployer) {
        // Get the calldata for the proposal
        IVoter.Action[] memory actions = OperatorMigrationPermissionsBuilder.getProposalCalldata();
        // Propose vote via permsataker
        proposeVote(actions);
        uint256 proposalId = voter.getProposalCount() - 1;

        for (uint256 i = 0; i < actions.length; i++) {
            (address target, bytes memory data) = voter.proposalPayload(proposalId, i);
            console.log("Action", i+1);
            console.log(target);
            console.logBytes(data);
            console.log("--------------------------------");
        }
    }
}