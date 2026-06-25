// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { PairAdder } from "src/dao/operators/PairAdder.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

contract DeployPairAdderV2 is Script {
    function run() public returns (address pairAdder) {
        vm.startBroadcast();
        PairAdder deployed = new PairAdder(Protocol.CORE, Protocol.REGISTRY);
        vm.stopBroadcast();

        pairAdder = address(deployed);
        require(address(deployed.core()) == Protocol.CORE, "wrong core");
        require(deployed.registry() == Protocol.REGISTRY, "wrong registry");

        console.log("pair adder deployed at", pairAdder);
    }
}
