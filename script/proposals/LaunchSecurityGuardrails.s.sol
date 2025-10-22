// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { console } from "lib/forge-std/src/console.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";
import { ResupplyPairConvex } from "src/protocol/pair/ResupplyPairConvex.sol";

contract LaunchSecurityGuardrails is BaseAction, BaseProposal {

    function run() public isBatch(deployer) {
        // Build the calldata for the proposal
        IVoter.Action[] memory actions = buildProposalCalldata();

        // Propose vote via permsataker
        proposeVote(actions, "Introduce Additional Protocol Security Guardrails");
        uint256 proposalId = voter.getProposalCount() - 1;

        for (uint256 i = 0; i < actions.length; i++) {
            (address target, bytes memory data) = voter.proposalPayload(proposalId, i);
            console.log("Action", i+1);
            console.log(target);
            console.logBytes(data);
            console.log("--------------------------------");
        }

        maxGasPerBatch = type(uint256).max;
        deployMode = DeployMode.PRODUCTION;
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true, 549);
    }

    function buildProposalCalldata() public override view returns (IVoter.Action[] memory actions) {
        // Set code in new and old pair deployers
        IVoter.Action[] memory pairDeployerActions = buildPairDeployerCalldata();
        // Update permissions for the new operators
        IVoter.Action[] memory permissionUpdateActions = buildPermissionUpdateCalldata();
        // Build all calldata for oracle update
        IVoter.Action[] memory oracleActions = buildOracleUpdateCalldata();
        // Merge all actions into a single array
        IVoter.Action[] memory actions = new IVoter.Action[](pairDeployerActions.length + permissionUpdateActions.length + oracleActions.length);
        uint256 actionIndex = 0;
        for (uint256 i = 0; i < pairDeployerActions.length; i++) actions[actionIndex++] = pairDeployerActions[i];
        for (uint256 i = 0; i < permissionUpdateActions.length; i++) actions[actionIndex++] = permissionUpdateActions[i];
        for (uint256 i = 0; i < oracleActions.length; i++) actions[actionIndex++] = oracleActions[i];

        return actions;
    }

    function buildPairDeployerCalldata() internal view returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](2);
        // Clear code from the deprecated pair deployer
        actions[0] = IVoter.Action({
            target: Protocol.PAIR_DEPLOYER_V1,
            data: abi.encodeWithSelector(
                IResupplyPairDeployer.setCreationCode.selector,
                new bytes(0)
            )
        });
        // Set new code for the new pair deployer
        actions[1] = IVoter.Action({
            target: Protocol.PAIR_DEPLOYER_V2,
            data: abi.encodeWithSelector(
                IResupplyPairDeployer.setCreationCode.selector,
                type(ResupplyPairConvex).creationCode
            )
        });
    }

    function buildOracleUpdateCalldata() internal view returns (IVoter.Action[] memory actions) {
        address[] memory pairs = registry.getAllPairAddresses();
        uint256 numPairs = pairs.length;
        // Oracle updates for all pairs
        IVoter.Action[] memory oracleActions = new IVoter.Action[](numPairs);
        address oracle;
        for (uint256 i = 0; i < numPairs; i++) {
            if (pairs[i] == Protocol.PAIR_CURVELEND_WSTUR_CRVUSD) {
                oracle = address(0);
            } else {
                oracle = Protocol.BASIC_VAULT_ORACLE;
            }
            oracleActions[i] = IVoter.Action({
                target: pairs[i],
                data: abi.encodeWithSelector(
                    IResupplyPair.setOracle.selector,
                    oracle
                )
            });
        }
        return oracleActions;
    }

    function buildPermissionUpdateCalldata() internal view returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](2);
        // Borrow Limit Controller
        actions[0] = PermissionHelper.buildOperatorPermissionAction(
            Protocol.BORROW_LIMIT_CONTROLLER,       // caller
            address(0),                             // target
            IResupplyPair.setBorrowLimit.selector,  // selector
            true                                    // enable
        );
        // Pair Adder
        actions[1] = PermissionHelper.buildOperatorPermissionAction(
            Protocol.PAIR_ADDER,
            Protocol.REGISTRY,
            IResupplyRegistry.addPair.selector,
            true
        );
    }
}