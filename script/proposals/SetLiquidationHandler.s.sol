// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Mainnet, Protocol } from "src/Constants.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";

contract SetLiquidationHandler is Script {
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    IVoter public constant voter = IVoter(Protocol.VOTER);

    string public constant DESCRIPTION = "Replace liquidation handler with capped fee-based incentives and lower maximum redemption discount to 0.1 bps";
    uint256 public constant MAX_REDEMPTION_DISCOUNT = 1e13; // 0.1 bps (0.001%)
    address public immutable previousLiquidationHandler;

    constructor() {
        require(block.chainid == Mainnet.CHAIN_ID, "unsupported chain");
        require(Protocol.LIQUIDATION_HANDLER.code.length > 0, "handler not deployed");
        LiquidationHandler handler = LiquidationHandler(Protocol.LIQUIDATION_HANDLER);
        require(address(handler.core()) == Protocol.CORE, "wrong handler core");
        require(handler.registry() == Protocol.REGISTRY, "wrong handler registry");
        require(handler.insurancePool() == Protocol.INSURANCE_POOL, "wrong handler insurance pool");

        previousLiquidationHandler = registry.liquidationHandler();
        require(previousLiquidationHandler != address(0), "handler not set");
        require(previousLiquidationHandler != Protocol.LIQUIDATION_HANDLER, "handler already replaced");
    }

    function run() public {
        IVoter.Action[] memory actions = buildProposalCalldata();
        console.log("Previous liquidation handler:", previousLiquidationHandler);
        console.log("New liquidation handler:", Protocol.LIQUIDATION_HANDLER);
        console.log("Maximum redemption discount (1e18 precision):", MAX_REDEMPTION_DISCOUNT);
        for (uint256 i = 0; i < actions.length; i++) {
            console.log("Action", i + 1);
            console.log(actions[i].target);
            console.logBytes(actions[i].data);
        }

        vm.startBroadcast();
        (, address proposer,) = vm.readCallers();
        uint256 proposalId = voter.createNewProposal(proposer, actions, DESCRIPTION);
        vm.stopBroadcast();

        console.log("Proposal created by:", proposer);
        console.log("Proposal ID:", proposalId);
    }

    function buildProposalCalldata() public view returns (IVoter.Action[] memory actions) {
        // Preflight only: recheck before execution to avoid stranding old-handler collateral or debt.
        address[] memory pairs = registry.getAllPairAddresses();
        for (uint256 i = 0; i < pairs.length; i++) {
            address collateral = IResupplyPair(pairs[i]).collateral();
            require(LiquidationHandler(previousLiquidationHandler).debtByCollateral(collateral) == 0, "old handler has debt");
            require(IERC20(collateral).balanceOf(previousLiquidationHandler) == 0, "old handler has collateral");
        }

        actions = new IVoter.Action[](2);

        // Update the active handler and protected LIQUIDATION_HANDLER registry entry together.
        actions[0] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.setLiquidationHandler.selector,
                Protocol.LIQUIDATION_HANDLER
            )
        });

        // Lower the redemption discount while preserving the existing usage settings.
        RedemptionHandler redemptionHandler = RedemptionHandler(registry.redemptionHandler());
        actions[1] = IVoter.Action({
            target: address(redemptionHandler),
            data: abi.encodeWithSelector(
                RedemptionHandler.setDiscountInfo.selector,
                redemptionHandler.usageDecayRate(), // existing decay rate
                redemptionHandler.maxUsage(), // existing usage cap
                MAX_REDEMPTION_DISCOUNT // 0.1 bps
            )
        });
    }
}
