// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Prisma } from "src/Constants.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { ISwapperOdos } from "src/interfaces/ISwapperOdos.sol";
import { IInsurancePool } from "src/interfaces/IInsurancePool.sol";
import { IPrismaFeeReceiver } from "src/interfaces/prisma/IPrismaFeeReceiver.sol";
import { IVestManager } from "src/interfaces/IVestManager.sol";
import { PermissionUpdate } from "script/utils/PermissionHelper.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";

library OperatorMigrationPermissions {
    
    function permissions() internal pure returns (PermissionUpdate[] memory) {
        PermissionUpdate[] memory permissions = new PermissionUpdate[](36);
        uint256 i = 0;
        
        // ===== ENABLE =====
        // Pair Adder
        permissions[i++] = PermissionUpdate(Protocol.PAIR_ADDER, Protocol.REGISTRY, IResupplyRegistry.addPair.selector, true);
        
        // Borrow Limit Controller
        permissions[i++] = PermissionUpdate(Protocol.BORROW_LIMIT_CONTROLLER, address(0), IResupplyPair.setBorrowLimit.selector, true);
        
        // Guardian Proxy
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IResupplyPair.pause.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IVoter.setMinTimeBetweenProposals.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IVoter.updateProposalDescription.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IBorrowLimitController.cancelRamp.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.CORE, ICore.setVoter.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.REGISTRY, IResupplyRegistry.setAddress.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.SWAPPER_ODOS, ISwapperOdos.revokeApprovals.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.INSURANCE_POOL, IInsurancePool.setWithdrawTimers.selector, true);
        
        // Treasury Manager Proxy
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveToken.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveTokenExact.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveETH.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveETHExact.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.setTokenApproval.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.safeExecute.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.execute.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, IPrismaFeeReceiver.transferToken.selector, true);
        permissions[i++] = PermissionUpdate(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, IPrismaFeeReceiver.setTokenApproval.selector, true);
        
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
