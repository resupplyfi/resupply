// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IUpgradeableOperator } from "src/interfaces/IUpgradeableOperator.sol";
import { Protocol } from "src/Constants.sol";
import { ProposeRedemptionOperator as RedemptionOperatorProposal } from "script/proposals/ProposeRedemptionOperator.s.sol";

contract ProposalRedemptionOperatorTest is BaseProposalTest {
    RedemptionOperatorProposal public proposal;
    bool public proposalExecuted;

    function setUp() public override {
        super.setUp();
        proposal = new RedemptionOperatorProposal();

        if (
            proposal.NEW_REDEMPTION_HANDLER() == address(0) ||
            proposal.REDEMPTION_OPERATOR() == address(0) ||
            proposal.NEW_REUSD_ORACLE() == address(0) ||
            proposal.UPGRADE_OPERATOR() == address(0)
        ) {
            return;
        }

        uint256 proposalId = createProposal(proposal.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
        proposalExecuted = true;
    }

    function test_UpgradeOperatorPermission() public {
        if (!proposalExecuted) return;
        (bool enabled,) = core.operatorPermissions(
            proposal.UPGRADE_OPERATOR(),
            proposal.REDEMPTION_OPERATOR(),
            IUpgradeableOperator.upgradeToAndCall.selector
        );
        assertTrue(enabled, "upgrade permission not granted");

        (enabled,) = core.operatorPermissions(
            proposal.UPGRADE_OPERATOR(),
            Protocol.OPERATOR_GUARDIAN_PROXY,
            IUpgradeableOperator.upgradeToAndCall.selector
        );
        assertTrue(enabled, "guardian upgrade permission not granted");
    }

    function test_GuardianUpdateGuardSettingsPermission() public {
        if (!proposalExecuted) return;
        (bool enabled,) = core.operatorPermissions(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            proposal.NEW_REDEMPTION_HANDLER(),
            IRedemptionHandler.updateGuardSettings.selector
        );
        assertTrue(enabled, "guardian permission not granted");
    }

    function test_RegistryAddressesSet() public {
        if (!proposalExecuted) return;
        assertEq(registry.redemptionHandler(), proposal.NEW_REDEMPTION_HANDLER());
        assertEq(registry.getAddress("REDEMPTION_OPERATOR"), proposal.REDEMPTION_OPERATOR());
        assertEq(registry.getAddress("REUSD_ORACLE"), proposal.NEW_REUSD_ORACLE());
    }

    function test_GuardSettingsUpdated() public {
        if (!proposalExecuted) return;
        address handler = proposal.NEW_REDEMPTION_HANDLER();
        (bool ok, bytes memory data) = handler.staticcall(abi.encodeWithSignature("guardEnabled()"));
        require(ok, "guardEnabled unavailable");
        assertEq(abi.decode(data, (bool)), proposal.GUARD_ENABLED());

        (ok, data) = handler.staticcall(abi.encodeWithSignature("permissionlessPriceThreshold()"));
        require(ok, "permissionlessPriceThreshold unavailable");
        assertEq(abi.decode(data, (uint256)), proposal.PERMISSIONLESS_PRICE_THRESHOLD());
    }
}
