pragma solidity 0.8.28;

import { BadDebtPayer } from "src/dao/misc/BadDebtPayer.sol";
import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "lib/forge-std/src/console.sol";


contract DeployBadDebtPayer is Script {
    
    function run() public{
        vm.startBroadcast(vm.envUint("RESUPPLY_PK"));
        BadDebtPayer badDebtPayer = new BadDebtPayer();
        console.log("BadDebtPayer deployed at", address(badDebtPayer));
        vm.stopBroadcast();
    }
}