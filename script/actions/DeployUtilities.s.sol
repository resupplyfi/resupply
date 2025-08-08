pragma solidity 0.8.30;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Utilities } from "src/protocol/Utilities.sol";
import { console } from "lib/forge-std/src/console.sol";

contract DeployUtilities is BaseAction {    
    
    function run() public {
        vm.startBroadcast(vm.envUint("PK_RESUPPLY"));
        Utilities utilities = new Utilities(Protocol.REGISTRY);
        vm.stopBroadcast();
    }
}