// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RedemptionOperator } from "src/dao/operators/RedemptionOperator.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";

contract DeployRedemptionOperator is BaseAction {
    function run() public {
        address[] memory approved = new address[](1);
        approved[0] = Protocol.DEPLOYER;
        bytes memory initializerData = abi.encodeCall(RedemptionOperator.initialize, approved);

        vm.startBroadcast(vm.envUint("PK_RESUPPLY"));
        deployUUPSProxy(
            "RedemptionOperator.sol:RedemptionOperator",
            initializerData,
            false
        );
        vm.stopBroadcast();
    }
}
