// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Prisma } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { ISwapperOdos } from "src/interfaces/ISwapperOdos.sol";
import { IInsurancePool } from "src/interfaces/IInsurancePool.sol";
import { IPrismaFeeReceiver } from "src/interfaces/prisma/IPrismaFeeReceiver.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVestManager } from "src/interfaces/IVestManager.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";

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
        
        // Build pair deployer code set actions
        IVoter.Action[] memory pairDeploymentActions = buildPairDeploymentCalldata();
        // Build all calldata for oracle update and operator permission changes
        IVoter.Action[] memory oracleActions = buildOracleUpdateCalldata();
        // Actions in ./data/OperatorMigrationPermissions.sol
        IVoter.Action[] memory permissionActions = buildPermissionUpdateCalldata();

        // Merge all actions into a single array
        IVoter.Action[] memory actions = new IVoter.Action[](pairDeploymentActions.length + oracleActions.length + permissionActions.length);
        uint256 actionIndex = 0;
        for (uint256 i = 0; i < pairDeploymentActions.length; i++) actions[actionIndex++] = pairDeploymentActions[i];
        for (uint256 i = 0; i < oracleActions.length; i++) actions[actionIndex++] = oracleActions[i];
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

    function buildPairDeploymentCalldata() internal view returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](2);
        // Clear code from the deprecated pair deployer
        actions[0] = IVoter.Action({
            target: Protocol.PAIR_DEPLOYER_V1,
            data: abi.encodeWithSelector(
                IResupplyPairDeployer.setCreationCode.selector,
                ""
            )
        });
        // Set new code for the new pair deployer
        actions[1] = IVoter.Action({
            target: Protocol.PAIR_DEPLOYER_V2,
            data: abi.encodeWithSelector(
                IResupplyPairDeployer.setCreationCode.selector,
                type(ResupplyPair).creationCode
            )
        });
    }

    function buildOracleUpdateCalldata() internal view returns (IVoter.Action[] memory actions) {
        address[] memory pairs = registry.getAllPairAddresses();
        uint256 numPairs = pairs.length;
        // Oracle updates for all pairs
        IVoter.Action[] memory oracleActions = new IVoter.Action[](numPairs);
        for (uint256 i = 0; i < numPairs; i++) {
            oracleActions[i] = IVoter.Action({
                target: pairs[i],
                data: abi.encodeWithSelector(
                    IResupplyPair.setOracle.selector,
                    Protocol.BASIC_VAULT_ORACLE
                )
            });
        }
        return oracleActions;
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