// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IUpgradeableOperator } from "src/interfaces/IUpgradeableOperator.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { Protocol } from "src/Constants.sol";

contract ProposeRedemptionOperator is BaseAction, BaseProposal {
    // TODO: replace placeholders
    address public constant NEW_REDEMPTION_HANDLER = address(0);
    address public constant REDEMPTION_OPERATOR = address(0);
    address public constant NEW_REUSD_ORACLE = address(0);
    address public constant UPGRADE_OPERATOR = address(0);

    bool public constant GUARD_ENABLED = true;
    uint256 public constant PERMISSIONLESS_PRICE_THRESHOLD = .985e18;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Set redemption operator, handler, and oracle");

        if (deployMode == DeployMode.PRODUCTION) {
            require(NEW_REDEMPTION_HANDLER != address(0), "RedemptionHandler not set");
            require(REDEMPTION_OPERATOR != address(0), "RedemptionOperator not set");
            require(NEW_REUSD_ORACLE != address(0), "REUSD_ORACLE not set");
            require(UPGRADE_OPERATOR != address(0), "UpgradeOperator not set");
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](7);

        // Set guard settings in new Redemption Handler
        actions[0] = IVoter.Action({
            target: NEW_REDEMPTION_HANDLER,
            data: abi.encodeWithSelector(
                IRedemptionHandler.updateGuardSettings.selector,
                GUARD_ENABLED,
                PERMISSIONLESS_PRICE_THRESHOLD
            )
        });

        // Give Upgrade Operator permission to upgrade impl for Redemption Operator
        actions[1] = setOperatorPermission(
            UPGRADE_OPERATOR,
            REDEMPTION_OPERATOR,
            IUpgradeableOperator.upgradeToAndCall.selector,
            true
        );

        // Update Redemption Handler registry key
        actions[2] = IVoter.Action({
            target: address(registry),
            data: abi.encodeWithSelector(
                IResupplyRegistry.setRedemptionHandler.selector,
                NEW_REDEMPTION_HANDLER
            )
        });

        // Add REDEMPTION_OPERATOR registry key
        actions[3] = IVoter.Action({
            target: address(registry),
            data: abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                "REDEMPTION_OPERATOR",
                REDEMPTION_OPERATOR
            )
        });

        // Update REUSD_ORACLE registry key
        actions[4] = IVoter.Action({
            target: address(registry),
            data: abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                "REUSD_ORACLE",
                NEW_REUSD_ORACLE
            )
        });

        // Allow Guardian to update redemption guard settings
        actions[5] = setOperatorPermission(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            NEW_REDEMPTION_HANDLER,
            IRedemptionHandler.updateGuardSettings.selector,
            true
        );

        // Allow Upgrade Operator to upgrade Guardian proxy
        actions[6] = setOperatorPermission(
            UPGRADE_OPERATOR,
            Protocol.OPERATOR_GUARDIAN_PROXY,
            IUpgradeableOperator.upgradeToAndCall.selector,
            true
        );
    }
}
