// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Prisma } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { console } from "lib/forge-std/src/console.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { PermissionUpdate, PermissionHelper } from "script/utils/PermissionHelper.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { ISwapperOdos } from "src/interfaces/ISwapperOdos.sol";
import { IInsurancePool } from "src/interfaces/IInsurancePool.sol";
import { IPrismaFeeReceiver } from "src/interfaces/prisma/IPrismaFeeReceiver.sol";
import { IVestManager } from "src/interfaces/IVestManager.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IGuardian } from "src/interfaces/IGuardian.sol";

contract LaunchOperatorsAndPermissions is BaseAction, BaseProposal {

    function run() public isBatch(deployer) {
        // Get the calldata for the proposal
        IVoter.Action[] memory actions = buildProposalCalldata();
        // Propose vote via permsataker
        proposeVote(actions, "Migrate Operators and Permissions");
        uint256 proposalId = voter.getProposalCount() - 1;

        for (uint256 i = 0; i < actions.length; i++) {
            (address target, bytes memory data) = voter.proposalPayload(proposalId, i);
            console.log("Action", i+1);
            console.log(target);
            console.logBytes(data);
            console.log("--------------------------------");
        }
    }

    function buildProposalCalldata() public view returns (IVoter.Action[] memory actions) {
        IVoter.Action[] memory guardedRegistryKeyActions = buildGuardedRegistryKeyCalldata();
        IVoter.Action[] memory permissionActions = PermissionHelper.buildPermissionActions(permissions());

        // Merge all actions into a single array
        IVoter.Action[] memory actions = new IVoter.Action[](guardedRegistryKeyActions.length + permissionActions.length);
        uint256 actionIndex = 0;
        for (uint256 i = 0; i < guardedRegistryKeyActions.length; i++) actions[actionIndex++] = guardedRegistryKeyActions[i];
        for (uint256 i = 0; i < permissionActions.length; i++) actions[actionIndex++] = permissionActions[i];
        
        return actions;
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

    function permissions() internal pure returns (PermissionUpdate[] memory) {
        PermissionUpdate[] memory permissions = new PermissionUpdate[](34);
        uint256 i = 0;
        
        // ===== ENABLE =====
        // Guardian Proxy
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IResupplyPair.pause.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IVoter.setMinTimeBetweenProposals.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IVoter.updateProposalDescription.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IBorrowLimitController.cancelRamp.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), ISwapperOdos.revokeApprovals.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.INSURANCE_POOL, IInsurancePool.setWithdrawTimers.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.REGISTRY, IResupplyRegistry.setAddress.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.DEPLOYER, Protocol.CORE, ICore.setVoter.selector, true);

        // Treasury Manager Proxy
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveToken.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveTokenExact.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveETH.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveETHExact.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.setTokenApproval.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.safeExecute.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.execute.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.transferToken.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.setTokenApproval.selector, true);
        
        // ===== DISABLE DEPRECATED PERMISSIONS =====
        // Old Guardian
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IVoter.updateProposalDescription.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.VOTER_DEPRECATED, IVoter.updateProposalDescription.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.REGISTRY, IResupplyRegistry.setAddress.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.CORE, ICore.setVoter.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IResupplyPair.pause.selector, false);

        // Old Treasury Manager
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveToken.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveTokenExact.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveETH.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveETHExact.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.setTokenApproval.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.execute.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.safeExecute.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.transferToken.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.setTokenApproval.selector, false);

        // Other
        permissions[i++] = PermissionUpdate(Protocol.DEPLOYER, Protocol.VEST_MANAGER, IVestManager.setLockPenaltyMerkleRoot.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.DEPLOYER, Protocol.VOTER_DEPRECATED_3, IVoter.updateProposalDescription.selector, false);
        permissions[i++] = PermissionUpdate(Protocol.DEPLOYER, Protocol.SWAPPER_ODOS, ISwapperOdos.revokeApprovals.selector, false);
        
        return permissions;
    }
}