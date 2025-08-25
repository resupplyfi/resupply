// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { console } from "lib/forge-std/src/console.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract CancelProposalPermissions is BaseAction, BaseProposal {
    function run() public isBatch(deployer) {
        IVoter.Action[] memory actions = step1();
        // IVoter.Action[] memory actions = step2();
        // IVoter.Action[] memory actions = step3();
        proposeVote(actions, "Migrate cancelProposal permission to new guardian step 2 of 3");
        uint256 proposalId = voter.getProposalCount() - 1;

        for (uint256 i = 0; i < actions.length; i++) {
            (address target, bytes memory data) = voter.proposalPayload(proposalId, i);
            console.log("Action", i+1);
            console.log(target);
            console.logBytes(data);
            console.log("--------------------------------");
        }

        if (deployMode == DeployMode.PRODUCTION){
            executeBatch(true);
        }
    }

    function step1() public view returns (IVoter.Action[] memory) {
        IVoter.Action[] memory actions = new IVoter.Action[](1);
        if (!PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IVoter.cancelProposal.selector)) {
            actions[0] = PermissionHelper.buildOperatorPermissionAction(
                Protocol.OPERATOR_GUARDIAN_PROXY,
                address(0),
                IVoter.cancelProposal.selector,
                true
            );
            console.log("Adding permission to OPERATOR_GUARDIAN_PROXY");
        }
        require(actions.length > 0, "No permission to add");
        return actions;
    }

    function step2() public view returns (IVoter.Action[] memory) {
        IVoter.Action[] memory actions = new IVoter.Action[](1);
        if (PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IVoter.cancelProposal.selector)) {
            actions[0] = PermissionHelper.buildOperatorPermissionAction(
                Protocol.OPERATOR_GUARDIAN_OLD,
                address(0),
                IVoter.cancelProposal.selector,
                false
            );
            console.log("Removing permission from OPERATOR_GUARDIAN_OLD on address(0)");
        }
        require(actions.length > 0, "No permission to remove");
        return actions;
    }

    function step3() public view returns (IVoter.Action[] memory) {
        IVoter.Action[] memory actions = new IVoter.Action[](1);
        if (PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.VOTER_DEPRECATED, IVoter.cancelProposal.selector)) {
            actions[0] = PermissionHelper.buildOperatorPermissionAction(
                Protocol.OPERATOR_GUARDIAN_OLD,
                Protocol.VOTER_DEPRECATED,
                IVoter.cancelProposal.selector,
                false
            );
            console.log("Removing permission from OPERATOR_GUARDIAN_OLD on address(voter)");
        }
        require(actions.length > 0, "No permission to remove");
        return actions;
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {}
}