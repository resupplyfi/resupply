// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { console } from "lib/forge-std/src/console.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";
import { OperatorMigrationPermissions } from "script/proposals/data/OperatorMigrationPermissions.sol";
import { IGuardian } from "src/interfaces/IGuardian.sol";

interface IPermastakerOperator {
    function safeExecute(address target, bytes calldata data) external;
    function createNewProposal(IVoter.Action[] calldata actions, string calldata description) external;
}

contract LaunchFixes is BaseAction {
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    ICore public constant _core = ICore(Protocol.CORE);
    IVoter public voter;
    address public constant deployer = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    IPermastakerOperator public constant PERMA_STAKER_OPERATOR = IPermastakerOperator(0x3419b3FfF84b5FBF6Eec061bA3f9b72809c955Bf);

    function run() public isBatch(deployer) {
        voter = IVoter(registry.getAddress("VOTER"));
        
        // "Protected keys" in registry are already guarded
        IVoter.Action[] memory guardedRegistryKeyActions = buildGuardedRegistryKeyCalldata();
        // Actions in ./data/OperatorMigrationPermissions.sol
        IVoter.Action[] memory permissionActions = 
            PermissionHelper.buildPermissionActions(OperatorMigrationPermissions.permissions());

        // Merge all actions into a single array
        IVoter.Action[] memory actions = new IVoter.Action[](guardedRegistryKeyActions.length + permissionActions.length);
        uint256 actionIndex = 0;
        for (uint256 i = 0; i < guardedRegistryKeyActions.length; i++) actions[actionIndex++] = guardedRegistryKeyActions[i];
        for (uint256 i = 0; i < permissionActions.length; i++) actions[actionIndex++] = permissionActions[i];

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

    function buildGuardedRegistryKeyCalldata() internal view returns (IVoter.Action[] memory actions) {
        // Protected keys in registry are already guarded
        string[] memory guardedKeys = new string[](4);
        guardedKeys[0] = "PAIR_DEPLOYER";
        guardedKeys[1] = "VOTER";
        guardedKeys[2] = "EMISSIONS_CONTROLLER";
        guardedKeys[3] = "REUSD_ORACLE";

        actions = new IVoter.Action[](guardedKeys.length);
        for (uint256 i = 0; i < guardedKeys.length; i++) {
            actions[i] = IVoter.Action({
                target: Protocol.OPERATOR_GUARDIAN_PROXY,
                data: abi.encodeWithSelector(
                    IGuardian.setGuardedRegistryKey.selector,
                    guardedKeys[i],
                    true
                )
            });
        }
        return actions;
    }

    function proposeVote(IVoter.Action[] memory actions) public {
        addToBatch(
            address(PERMA_STAKER_OPERATOR),
            abi.encodeWithSelector(
                IPermastakerOperator.createNewProposal.selector,
                actions,
                "Configure Operator Permissions"
            )
        );
    }
}