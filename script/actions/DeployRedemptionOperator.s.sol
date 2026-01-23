// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { RedemptionOperator } from "src/dao/operators/RedemptionOperator.sol";

contract DeployRedemptionOperator is Script {
    uint256 constant REUSD_DUST = 1e18;

    function run() public {
        uint256 pk = vm.envUint("PK_RESUPPLY");
        vm.startBroadcast(pk);
        new RedemptionOperator(REUSD_DUST);
        vm.stopBroadcast();
    }
}
