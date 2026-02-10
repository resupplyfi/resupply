// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { console } from "forge-std/console.sol";

import { UpgradeOperator } from "src/dao/operators/UpgradeOperator.sol";
import { RedemptionOperator } from "src/dao/operators/RedemptionOperator.sol";
import { ReusdOracle } from "src/protocol/ReusdOracle.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { UnsafeUpgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";

contract DeployRedemptionOperatorSuite is BaseAction {
    function run() public {
        address[] memory approved = new address[](3);

        // Approved redeemers
        approved[0] = Protocol.DEPLOYER;
        approved[1] = 0x1ba323F8a6544b81Dc1F068b1400A6ebe7Ea0f52;
        approved[2] = 0x051C42Ee7A529410a10E5Ec11B9E9b8bA7cbb795;

        vm.startBroadcast(loadPrivateKey());

        address upgradeOperator = _deployUpgradeOperator();
        address redemptionHandler = _deployRedemptionHandler();
        address reusdOracle = _deployReusdOracle();
        address redemptionOperator = _deployRedemptionOperatorProxy(approved);

        vm.stopBroadcast();
    }

    function _deployUpgradeOperator() internal returns (address deployed) {
        UpgradeOperator operator = new UpgradeOperator(Protocol.CORE, Protocol.DEPLOYER);
        deployed = address(operator);
        console.log("UpgradeOperator deployed at", deployed);
    }

    function _deployRedemptionHandler() internal returns (address deployed) {
        RedemptionHandler handler = new RedemptionHandler(Protocol.CORE, Protocol.REGISTRY, Protocol.UNDERLYING_ORACLE);
        deployed = address(handler);
        console.log("RedemptionHandler deployed at", deployed);
    }

    function _deployReusdOracle() internal returns (address deployed) {
        ReusdOracle oracle = new ReusdOracle("reUSD oracle");
        deployed = address(oracle);
        console.log("ReusdOracle deployed at", deployed);
    }

    function _deployRedemptionOperatorProxy(address[] memory approved) internal returns (address proxy) {
        bytes memory initializerData = abi.encodeCall(
            RedemptionOperator.initialize,
            (Protocol.DEPLOYER, approved)
        );

        RedemptionOperator impl = new RedemptionOperator();
        proxy = UnsafeUpgrades.deployUUPSProxy(address(impl), initializerData);

        console.log("RedemptionOperator impl deployed at", address(impl));
        console.log("RedemptionOperator proxy deployed at", proxy);
    }
}
