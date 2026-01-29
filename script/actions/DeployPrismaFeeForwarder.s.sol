pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { PrismaFeeForwarder } from "src/dao/operators/PrismaFeeForwarder.sol";

contract DeployPrismaFeeForwarder is BaseAction {    
    
    function run() public {
        vm.startBroadcast(loadPrivateKey());
        PrismaFeeForwarder forwarder = new PrismaFeeForwarder(Protocol.CORE);
        vm.stopBroadcast();
    }
}