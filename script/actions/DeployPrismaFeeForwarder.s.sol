pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { PrismaVeCrvOperator } from "src/dao/operators/PrismaVeCrvOperator.sol";

contract DeployPrismaFeeForwarder is BaseAction {    
    
    function run() public {
        vm.startBroadcast(loadPrivateKey());
        PrismaVeCrvOperator forwarder = new PrismaVeCrvOperator(Protocol.CORE);
        vm.stopBroadcast();
    }
}
