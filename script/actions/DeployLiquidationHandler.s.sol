// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Mainnet, Protocol } from "src/Constants.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";

/// @notice Deploys a replacement LiquidationHandler without changing the registry.
contract DeployLiquidationHandler is Script {
    string internal constant DEPLOYMENT_OBJECT = "liquidationHandlerDeployment";

    function run() public returns (LiquidationHandler handler) {
        require(block.chainid == Mainnet.CHAIN_ID, "unsupported chain");

        vm.startBroadcast();
        handler = new LiquidationHandler(Protocol.CORE, Protocol.REGISTRY, Protocol.INSURANCE_POOL);
        vm.stopBroadcast();

        require(address(handler.core()) == Protocol.CORE, "invalid core");
        require(handler.registry() == Protocol.REGISTRY, "invalid registry");
        require(handler.insurancePool() == Protocol.INSURANCE_POOL, "invalid insurance pool");
        require(handler.liquidateIncentiveShareBps() == 5000, "invalid incentive share");
        require(handler.maxLiquidateIncentive() == 25e18, "invalid maximum incentive");

        string memory json = vm.serializeUint(DEPLOYMENT_OBJECT, "chainId", block.chainid);
        json = vm.serializeAddress(DEPLOYMENT_OBJECT, "liquidationHandler", address(handler));
        json = vm.serializeAddress(DEPLOYMENT_OBJECT, "core", Protocol.CORE);
        json = vm.serializeAddress(DEPLOYMENT_OBJECT, "registry", Protocol.REGISTRY);
        json = vm.serializeAddress(DEPLOYMENT_OBJECT, "insurancePool", Protocol.INSURANCE_POOL);
        json = vm.serializeUint(DEPLOYMENT_OBJECT, "liquidateIncentiveShareBps", handler.liquidateIncentiveShareBps());
        json = vm.serializeUint(DEPLOYMENT_OBJECT, "maxLiquidateIncentive", handler.maxLiquidateIncentive());

        string memory outputDirectory = string.concat(vm.projectRoot(), "/data");
        string memory outputPath = string.concat(outputDirectory, "/deploy_liquidation_handler_", vm.toString(block.chainid), "_", vm.toString(address(handler)), ".json");
        vm.createDir(outputDirectory, true);
        vm.writeJson(json, outputPath);

        console.log("LiquidationHandler deployed at", address(handler));
        console.log("Deployment manifest written to", outputPath);
    }
}
