// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IUpgradeableOperator } from "src/interfaces/IUpgradeableOperator.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IUnderlyingOracle } from "src/interfaces/IUnderlyingOracle.sol";
import { IUpgradeOperator} from "src/interfaces/IUpgradeOperator.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { Protocol } from "src/Constants.sol";
import { ProposeRedemptionOperator } from "script/proposals/ProposeRedemptionOperator.s.sol";

contract ProposalRedemptionOperatorTest is BaseProposalTest {
    uint256 public constant PROP_ID = 16;
    ProposeRedemptionOperator public proposal;
    ResupplyPairDeployer.ConfigData public oldDefaultConfig;

    function setUp() public override {
        super.setUp();
        if (isProposalProcessed(PROP_ID)) vm.skip(true);
        proposal = new ProposeRedemptionOperator();
        if (
            proposal.NEW_REDEMPTION_HANDLER() == address(0) ||
            proposal.REDEMPTION_OPERATOR() == address(0) ||
            proposal.NEW_REUSD_ORACLE() == address(0) ||
            proposal.UPGRADE_OPERATOR() == address(0)
        ) {
            return;
        }
        oldDefaultConfig = ResupplyPairDeployer(address(deployer)).defaultConfigData();
        uint256 proposalId = createProposal(proposal.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_UpgradeOperatorPermission() public {
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
        (bool enabled,) = core.operatorPermissions(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            proposal.NEW_REDEMPTION_HANDLER(),
            IRedemptionHandler.updateGuardSettings.selector
        );
        assertTrue(enabled, "guardian permission not granted");
        
        // Upgrade Guardian proxy via manager
        IUpgradeOperator upgradeOp = IUpgradeOperator(proposal.UPGRADE_OPERATOR());
        address newImplementation = 0x74C85620F1459862834A947dB9441911BCEBF066;
        address manager = upgradeOp.manager();
        vm.prank(manager);
        upgradeOp.upgradeToAndCall(
            Protocol.OPERATOR_GUARDIAN_PROXY, // proxy
            newImplementation, // new impl
            "" // data
        );

        // already initialized, should not be re-initializeable
        vm.expectRevert();
        guardianContract.initialize(Protocol.DEPLOYER);

        address guardianUser = guardianContract.guardian();
        vm.prank(guardianUser);
        guardianContract.updateRedemptionGuardSettings(false, .90e18);

        assertEq(redemptionHandler.permissionlessPriceThreshold(), .90e18);
        assertFalse(redemptionHandler.guardEnabled());
    }

    function test_RegistryAddressesSet() public {
        assertEq(registry.redemptionHandler(), proposal.NEW_REDEMPTION_HANDLER());
        assertEq(registry.getAddress("REDEMPTION_OPERATOR"), proposal.REDEMPTION_OPERATOR());
        assertEq(registry.getAddress("REUSD_ORACLE"), proposal.NEW_REUSD_ORACLE());
    }

    function test_GuardSettingsUpdated() public {
        address handler = proposal.NEW_REDEMPTION_HANDLER();
        (bool ok, bytes memory data) = handler.staticcall(abi.encodeWithSignature("guardEnabled()"));
        require(ok, "guardEnabled unavailable");
        assertEq(abi.decode(data, (bool)), proposal.GUARD_ENABLED());

        (ok, data) = handler.staticcall(abi.encodeWithSignature("permissionlessPriceThreshold()"));
        require(ok, "permissionlessPriceThreshold unavailable");
        assertEq(abi.decode(data, (uint256)), proposal.PERMISSIONLESS_PRICE_THRESHOLD());
    }

    function test_DefaultDeployConfigMatchesFirstPair() public {
        address[] memory pairs = registry.getAllPairAddresses();
        require(pairs.length > 0, "no pairs");
        IResupplyPair pair = IResupplyPair(pairs[0]);

        ResupplyPairDeployer.ConfigData memory cfg =
            ResupplyPairDeployer(address(deployer)).defaultConfigData();
        assertEq(cfg.rateCalculator, pair.rateCalculator());
        assertEq(cfg.protocolRedemptionFee, pair.protocolRedemptionFee());
    }

    function test_DefaultConfigUpdated() public {
        ResupplyPairDeployer.ConfigData memory newConfig = ResupplyPairDeployer(address(deployer)).defaultConfigData();
        assertEq(newConfig.oracle, oldDefaultConfig.oracle, "oracle changed");
        assertEq(newConfig.maxLTV, oldDefaultConfig.maxLTV, "maxLTV changed");
        assertEq(newConfig.initialBorrowLimit, oldDefaultConfig.initialBorrowLimit, "borrow limit changed");
        assertEq(newConfig.liquidationFee, oldDefaultConfig.liquidationFee, "liquidation fee changed");
        assertEq(newConfig.mintFee, oldDefaultConfig.mintFee, "mint fee changed");
        assertEq(newConfig.rateCalculator, oldDefaultConfig.rateCalculator, "rate calculator not updated");
        assertEq(proposal.newProtocolRedemptionFee(), newConfig.protocolRedemptionFee, "fee doesnt match");
        assertNotEq(newConfig.protocolRedemptionFee, oldDefaultConfig.protocolRedemptionFee, "fee unchanged");
    }

    function test_RedemptionHandlerOracle() public {
        address configuredOracle = IRedemptionHandler(proposal.NEW_REDEMPTION_HANDLER()).underlyingOracle();
        assertEq(configuredOracle, Protocol.UNDERLYING_ORACLE, "wrong underlying oracle");
        assertEq(
            IUnderlyingOracle(configuredOracle).frxusd_oracle(),
            0x9B4a96210bc8D9D55b1908B465D8B0de68B7fF83,
            "wrong frxusd oracle"
        );
    }
}
