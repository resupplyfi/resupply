pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Utilities } from "src/protocol/Utilities.sol";

contract DeployUtilities is BaseAction {    
    
    function run() public {
        vm.startBroadcast(loadPrivateKey());
        Utilities utilities = new Utilities(Protocol.REGISTRY);
        vm.stopBroadcast();
    }
}