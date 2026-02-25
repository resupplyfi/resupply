pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { VeCrvOperator } from "src/dao/operators/VeCrvOperator.sol";

contract DeployVeCrvOperator is BaseAction {    
    
    function run() public {
        vm.startBroadcast(loadPrivateKey());
        VeCrvOperator forwarder = new VeCrvOperator(Protocol.CORE);
        vm.stopBroadcast();
    }
}
