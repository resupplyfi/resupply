// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Protocol } from "src/Constants.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { SetLiquidationHandler } from "script/proposals/SetLiquidationHandler.s.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";

contract SetLiquidationHandlerTest is BaseProposalTest {
    uint256 internal constant PRE_PROPOSAL_BLOCK = 26_230_115;

    SetLiquidationHandler public script;
    uint256 public usageDecayRateBefore;
    uint256 public maxUsageBefore;
    uint256 public baseRedemptionFeeBefore;

    function setUp() public override {
        super.setUp();
        // Replay from after deployment and before the registry replacement.
        vm.createSelectFork(vm.envString("MAINNET_URL"), PRE_PROPOSAL_BLOCK);
        pairs = registry.getAllPairAddresses();

        RedemptionHandler handler = RedemptionHandler(registry.redemptionHandler());
        usageDecayRateBefore = handler.usageDecayRate();
        maxUsageBefore = handler.maxUsage();
        baseRedemptionFeeBefore = handler.baseRedemptionFee();

        script = new SetLiquidationHandler();
        uint256 proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_RegistryLiquidationHandlerUpdated() public view {
        assertEq(script.previousLiquidationHandler(), Protocol.LIQUIDATION_HANDLER_OLD, "wrong previous handler");
        assertEq(registry.liquidationHandler(), Protocol.LIQUIDATION_HANDLER, "active handler not updated");
        assertEq(registry.getAddress("LIQUIDATION_HANDLER"), Protocol.LIQUIDATION_HANDLER, "registry entry not updated");
    }

    function test_NewHandlerConfiguration() public view {
        LiquidationHandler handler = LiquidationHandler(Protocol.LIQUIDATION_HANDLER);
        assertEq(address(handler.core()), Protocol.CORE, "wrong core");
        assertEq(handler.owner(), Protocol.CORE, "wrong owner");
        assertEq(handler.registry(), Protocol.REGISTRY, "wrong registry");
        assertEq(handler.insurancePool(), Protocol.INSURANCE_POOL, "wrong insurance pool");
        assertEq(handler.liquidateIncentiveShareBps(), 5_000, "wrong incentive share");
        assertEq(handler.maxLiquidateIncentive(), 25e18, "wrong maximum incentive");
    }

    function test_ProposalPayload() public view {
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        assertEq(actions.length, 2, "unexpected action count");
        assertEq(actions[0].target, Protocol.REGISTRY, "wrong target");
        assertEq(
            actions[0].data,
            abi.encodeWithSelector(IResupplyRegistry.setLiquidationHandler.selector, Protocol.LIQUIDATION_HANDLER),
            "wrong calldata"
        );

        assertEq(actions[1].target, registry.redemptionHandler(), "wrong redemption handler target");
        assertEq(
            actions[1].data,
            abi.encodeWithSelector(
                RedemptionHandler.setDiscountInfo.selector,
                usageDecayRateBefore,
                maxUsageBefore,
                uint256(1e13)
            ),
            "wrong redemption discount calldata"
        );
    }

    function test_RedemptionDiscountUpdatedWithoutChangingOtherSettings() public view {
        RedemptionHandler handler = RedemptionHandler(registry.redemptionHandler());
        assertEq(handler.maxDiscount(), 1e13, "maximum discount not set to 0.1 bps");
        assertEq(handler.usageDecayRate(), usageDecayRateBefore, "usage decay rate changed");
        assertEq(handler.maxUsage(), maxUsageBefore, "maximum usage changed");
        assertEq(handler.baseRedemptionFee(), baseRedemptionFeeBefore, "base redemption fee changed");
    }

    function test_HandlerAuthorizationFollowsRegistry() public {
        address collateral = IResupplyPair(pairs[0]).collateral();
        vm.expectRevert("!liq handler");
        LiquidationHandler(Protocol.LIQUIDATION_HANDLER_OLD).processCollateral(collateral);
        LiquidationHandler(Protocol.LIQUIDATION_HANDLER).processCollateral(collateral);

        vm.prank(Protocol.LIQUIDATION_HANDLER_OLD);
        vm.expectRevert("!liq handler");
        insurancePool.burnAssets(0);

        vm.prank(Protocol.LIQUIDATION_HANDLER);
        insurancePool.burnAssets(0);
    }

    function test_RejectsOutstandingOldHandlerDebt() public {
        address collateral = IResupplyPair(pairs[0]).collateral();
        vm.mockCall(
            Protocol.LIQUIDATION_HANDLER_OLD,
            abi.encodeWithSignature("debtByCollateral(address)", collateral),
            abi.encode(uint256(1))
        );

        vm.expectRevert("old handler has debt");
        script.buildProposalCalldata();
    }

    function test_RejectsOutstandingOldHandlerCollateral() public {
        address collateral = IResupplyPair(pairs[0]).collateral();
        vm.mockCall(
            collateral,
            abi.encodeWithSelector(IERC20.balanceOf.selector, Protocol.LIQUIDATION_HANDLER_OLD),
            abi.encode(uint256(1))
        );

        vm.expectRevert("old handler has collateral");
        script.buildProposalCalldata();
    }
}
