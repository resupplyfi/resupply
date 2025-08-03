pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Utilities } from "src/protocol/Utilities.sol";
import { console } from "lib/forge-std/src/console.sol";

contract DeployUtilities is BaseAction {    
    
    function run() public {
        vm.startBroadcast(vm.envUint("RESUPPLY_PK"));
        Utilities utilities = new Utilities(Protocol.REGISTRY);
        vm.stopBroadcast();
    }
}