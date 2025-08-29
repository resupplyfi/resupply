// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Prisma } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IGuardianUpgradeable } from "src/interfaces/IGuardianUpgradeable.sol";
import { ITreasuryManagerUpgradeable } from "src/interfaces/ITreasuryManagerUpgradeable.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IPrismaFeeReceiver } from "src/interfaces/prisma/IPrismaFeeReceiver.sol";
import { IVestManager } from "src/interfaces/IVestManager.sol";
import { ISwapperOdos } from "src/interfaces/ISwapperOdos.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { LaunchOperatorsAndPermissions } from "script/proposals/LaunchOperatorsAndPermissions.s.sol";

contract OperatorMigrationPermissionsTest is BaseProposalTest {
    IGuardianUpgradeable guardian = IGuardianUpgradeable(Protocol.OPERATOR_GUARDIAN_PROXY);
    LaunchOperatorsAndPermissions script;

    function setUp() public override {
        super.setUp();
        if (isProposalProcessed(7)) return;
        script = new LaunchOperatorsAndPermissions();
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }
    
    function test_GuardedKeysSet() public {
        assertTrue(guardian.guardedRegistryKeys("PAIR_DEPLOYER"));
        assertTrue(guardian.guardedRegistryKeys("VOTER"));
        assertTrue(guardian.guardedRegistryKeys("EMISSIONS_CONTROLLER"));
        assertTrue(guardian.guardedRegistryKeys("REUSD_ORACLE"));
    }

    function test_GuardianPermissionsAdded() public {
        // Guardian permissions
        IGuardianUpgradeable.Permissions memory permissions = guardian.viewPermissions();
        // assertTrue(permissions.cancelProposal, "cancelProposal permission not granted"); // This will be done in a dedicated proposal
        assertTrue(permissions.pauseAllPairs, "pauseAllPairs permission not granted");
        assertTrue(permissions.updateProposalDescription, "updateProposalDescription permission not granted");
        assertTrue(permissions.setRegistryAddress, "setRegistryAddress permission not granted");
        assertTrue(permissions.revokeSwapperApprovals, "revokeSwapperApprovals permission not granted");
        assertTrue(permissions.pauseIPWithdrawals, "pauseIPWithdrawals permission not granted");
        assertTrue(permissions.cancelRamp, "cancelRamp permission not granted");
    }

    function test_TreasuryManagerPermissionsAdded() public {
        // Treasury Manager permissions
        ITreasuryManagerUpgradeable.Permissions memory permissions = treasuryManager.viewPermissions();
        assertTrue(permissions.retrieveToken, "retrieveToken permission not granted");
        assertTrue(permissions.retrieveTokenExact, "retrieveTokenExact permission not granted");
        assertTrue(permissions.retrieveETH, "retrieveETH permission not granted");
        assertTrue(permissions.retrieveETHExact, "retrieveETHExact permission not granted");
        assertTrue(permissions.setTokenApproval, "setTokenApproval permission not granted");
        assertTrue(permissions.execute, "execute permission not granted");
        assertTrue(permissions.safeExecute, "safeExecute permission not granted");
        assertTrue(permissions.transferTokenFromPrismaFeeReceiver, "transferTokenFromPrismaFeeReceiver permission not granted");
        assertTrue(permissions.approveTokenFromPrismaFeeReceiver, "approveTokenFromPrismaFeeReceiver permission not granted");
    }

    function test_PermissionsRemoved() public {
        // Old Guardian
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IVoter.updateProposalDescription.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.VOTER_DEPRECATED, IVoter.updateProposalDescription.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.REGISTRY, IResupplyRegistry.setAddress.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.CORE, ICore.setVoter.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IResupplyPair.pause.selector));

        // Old Treasury Manager
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveToken.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveTokenExact.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveETH.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveETHExact.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.setTokenApproval.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.execute.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.safeExecute.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.transferToken.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.setTokenApproval.selector));

        // Other
        assertFalse(PermissionHelper.isEnabled(Protocol.DEPLOYER, Protocol.VEST_MANAGER, IVestManager.setLockPenaltyMerkleRoot.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.DEPLOYER, Protocol.VOTER_DEPRECATED_3, IVoter.updateProposalDescription.selector));
        assertFalse(PermissionHelper.isEnabled(Protocol.DEPLOYER, Protocol.SWAPPER_ODOS, ISwapperOdos.revokeApprovals.selector));
    }
}