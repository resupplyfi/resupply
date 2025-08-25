// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { Protocol, DeploymentConfig } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { CancelProposalPermissions } from "script/proposals/CancelProposalPermissions.s.sol";

contract CancelProposalPermissionsTest is BaseProposalTest {
    CancelProposalPermissions public script;

    function setUp() public override {
        super.setUp();
        script = new CancelProposalPermissions();
    }
    
    function test_CancelProposalPermissions() public {
        uint256 proposalId;
        console.log("1. Adding permission to OPERATOR_GUARDIAN_PROXY");
        IVoter.Action[] memory actions = script.step1();
        if (actions[0].target != address(0)) {
            proposalId = createProposal(actions);
            simulatePassingVote(proposalId);
            executeProposal(proposalId);
        }

        console.log("2. Removing permission from OPERATOR_GUARDIAN_OLD on address(0)");
        actions = script.step2();
        if (actions[0].target != address(0)) {
            proposalId = createProposal(actions);
            simulatePassingVote(proposalId);
            executeProposal(proposalId);
        }

        console.log("3. Removing permission from OPERATOR_GUARDIAN_OLD on address(voter)");
        actions = script.step3();
        if (actions[0].target != address(0)) {
            proposalId = createProposal(actions);
            simulatePassingVote(proposalId);
            executeProposal(proposalId);
        }

        assertEq(PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IVoter.cancelProposal.selector), true);
        assertEq(PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IVoter.cancelProposal.selector), false);
        assertEq(PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.VOTER_DEPRECATED, IVoter.cancelProposal.selector), false);
    }
}