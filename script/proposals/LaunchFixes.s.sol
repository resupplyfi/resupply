// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Prisma } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IOperatorGuardian } from "src/interfaces/operators/IOperatorGuardian.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { ISwapperOdos } from "src/interfaces/ISwapperOdos.sol";
import { IInsurancePool } from "src/interfaces/IInsurancePool.sol";
import { IPrismaFeeReceiver } from "src/interfaces/prisma/IPrismaFeeReceiver.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVestManager } from "src/interfaces/IVestManager.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";

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
    address[] public pairs;
    uint256 public numPairs;

    function run() public isBatch(deployer) {
        voter = IVoter(registry.getAddress("VOTER"));
        pairs = registry.getAllPairAddresses();
        numPairs = pairs.length;

        // Build all calldata for oracle update and operator permission changes
        IVoter.Action[] memory actions = buildCalldata();

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

    function buildCalldata() public returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](numPairs + 39);
        uint256 i = 0;
        for (; i < numPairs; i++) {
            actions[i] = IVoter.Action({
                target: pairs[i],
                data: abi.encodeWithSelector(
                    IResupplyPair.setOracle.selector,
                    Protocol.BASIC_VAULT_ORACLE
                )
            });
        }

        // ENABLE NEW PERMISSIONS
        // Pair Adder
        actions[i++] = _buildOperatorPermissionAction(Protocol.PAIR_ADDER, Protocol.CORE, IResupplyRegistry.addPair.selector, true);
        // Borrow Limit Controller
        actions[i++] = _buildOperatorPermissionAction(Protocol.BORROW_LIMIT_CONTROLLER, address(0), IResupplyPair.setBorrowLimit.selector, true);
        // Guardian Proxy
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IResupplyPair.pause.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IVoter.setMinTimeBetweenProposals.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.VOTER, IVoter.cancelProposal.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IVoter.updateProposalDescription.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.CORE, ICore.setVoter.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IResupplyRegistry.setAddress.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_PROXY, address(0), IBorrowLimitController.cancelRamp.selector, true);
        //NOTE: This one actually needs to get added to guardian
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.SWAPPER_ODOS, ISwapperOdos.revokeApprovals.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_PROXY, Protocol.INSURANCE_POOL, IInsurancePool.setWithdrawTimers.selector, true);
        // Treasury Manager Proxy
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveToken.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveTokenExact.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveETH.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.retrieveETHExact.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.setTokenApproval.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.safeExecute.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, ITreasury.execute.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, IPrismaFeeReceiver.transferToken.selector, true);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_PROXY, Protocol.TREASURY, IPrismaFeeReceiver.setTokenApproval.selector, true);

        // DISABLE OLD PERMISSIONS - We first do an `isEnabled` check to ensure the old permissions are actually enabled
        // Old Guardian
        require(isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IVoter.updateProposalDescription.selector), "Update Proposal Description Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IVoter.updateProposalDescription.selector, false);
        require(isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IVoter.cancelProposal.selector), "Cancel Proposal Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IVoter.cancelProposal.selector, false);
        require(isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.VOTER_DEPRECATED, IVoter.cancelProposal.selector), "Cancel Proposal Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.VOTER_DEPRECATED, IVoter.cancelProposal.selector, false);
        require(isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.VOTER_DEPRECATED, IVoter.updateProposalDescription.selector), "Update Proposal Description Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.VOTER_DEPRECATED, IVoter.updateProposalDescription.selector, false);
        require(isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.REGISTRY, IResupplyRegistry.setAddress.selector), "Set Address Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.REGISTRY, IResupplyRegistry.setAddress.selector, false);
        require(isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.CORE, ICore.setVoter.selector), "Set Voter Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_OLD, Protocol.CORE, ICore.setVoter.selector, false);
        require(isEnabled(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IResupplyPair.pause.selector), "Pause Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_OLD, address(0), IResupplyPair.pause.selector, false);

        // Old Treasury Manager
        require(isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveToken.selector), "Retrieve Token Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveToken.selector, false);
        require(isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveTokenExact.selector), "Retrieve Token Exact Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveTokenExact.selector, false);
        require(isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveETH.selector), "Retrieve ETH Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveETH.selector, false);
        require(isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveETHExact.selector), "Retrieve ETH Exact Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.retrieveETHExact.selector, false);
        require(isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.setTokenApproval.selector), "Set Token Approval Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.setTokenApproval.selector, false);
        require(isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.execute.selector), "Execute Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.execute.selector, false);
        require(isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.safeExecute.selector), "Safe Execute Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Protocol.TREASURY, ITreasury.safeExecute.selector, false);
        require(isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.transferToken.selector), "Transfer Token Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.transferToken.selector, false);
        require(isEnabled(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.setTokenApproval.selector), "Set Token Approval Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_TREASURY_MANAGER_OLD, Prisma.FEE_RECEIVER, IPrismaFeeReceiver.setTokenApproval.selector, false);

        // Other
        actions[i++] = _buildOperatorPermissionAction(Protocol.DEPLOYER, Protocol.VEST_MANAGER, IVestManager.setLockPenaltyMerkleRoot.selector, false);
        actions[i++] = _buildOperatorPermissionAction(Protocol.OPERATOR_GUARDIAN_OLD, 0x111111110d3e18e73CC2227A40B565043266DaC1, IVoter.updateProposalDescription.selector, false);
        require(isEnabled(Protocol.DEPLOYER, Protocol.SWAPPER_ODOS, ISwapperOdos.revokeApprovals.selector), "Revoke Approvals Not Enabled");
        actions[i++] = _buildOperatorPermissionAction(Protocol.DEPLOYER, Protocol.SWAPPER_ODOS, ISwapperOdos.revokeApprovals.selector, false);
    }

    function _buildOperatorPermissionAction(address caller, address target, bytes4 selector, bool enable) internal returns (IVoter.Action memory data) {
        data = IVoter.Action({
            target: address(Protocol.CORE),
            data: abi.encodeWithSelector(
                selector,
                caller,
                target,
                selector,
                enable,
                address(0) // Auth Hook
            )
        });
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

    function isEnabled(address caller, address target, bytes4 selector) public view returns (bool) {
        (bool authorized, IAuthHook hook) = _core.operatorPermissions(caller, target, selector);
        return authorized;
    }
}