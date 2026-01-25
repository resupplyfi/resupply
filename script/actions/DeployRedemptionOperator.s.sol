// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RedemptionOperator } from "src/dao/operators/RedemptionOperator.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { UnsafeUpgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";

contract DeployRedemptionOperator is BaseAction {
    function run() public {
        address[] memory approved = new address[](2);
        approved[0] = Protocol.DEPLOYER;
        approved[1] = 0x1ba323F8a6544b81Dc1F068b1400A6ebe7Ea0f52;
        bytes memory initializerData = abi.encodeCall(RedemptionOperator.initialize, approved);

        vm.startBroadcast(vm.envUint("PK_RESUPPLY"));
        RedemptionOperator impl = new RedemptionOperator();
        UnsafeUpgrades.deployUUPSProxy(address(impl), initializerData);
        vm.stopBroadcast();
    }
}
