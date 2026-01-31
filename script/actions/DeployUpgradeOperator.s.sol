// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { UpgradeOperator } from "src/dao/operators/UpgradeOperator.sol";
import { console } from "forge-std/console.sol";

contract DeployUpgradeOperator is BaseAction {
    function run() public {
        vm.startBroadcast(loadPrivateKey());
        UpgradeOperator operator = new UpgradeOperator(Protocol.CORE, Protocol.DEPLOYER);
        console.log("UpgradeOperator deployed at", address(operator));
        console.log("Manager", operator.manager());
        console.log("Owner (core)", operator.owner());
        vm.stopBroadcast();
    }
}
