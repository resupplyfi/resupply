// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RedemptionOperator } from "src/dao/operators/RedemptionOperator.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

/// @notice Deploys a new implementation for the existing redemption operator proxy.
/// @dev This script does not deploy, initialize, or upgrade a proxy.
contract DeployRedemptionOperator is Script {
    function run() public returns (address implementation) {
        vm.startBroadcast();
        implementation = address(new RedemptionOperator());
        vm.stopBroadcast();

        require(implementation.code.length != 0, "implementation deployment failed");
        console.log("RedemptionOperator implementation deployed at", implementation);
    }
}
