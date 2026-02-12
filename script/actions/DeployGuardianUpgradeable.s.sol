// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { console } from "forge-std/console.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";

contract DeployGuardianUpgradeable is BaseAction {
    address internal constant GUARDIAN_PROXY = Protocol.OPERATOR_GUARDIAN_PROXY;
    address public currentImplementation;

    function run() public {
        vm.startBroadcast(loadPrivateKey());
        currentImplementation = Upgrades.getImplementationAddress(GUARDIAN_PROXY);
        address newImplementation = deployImplementation(
            "GuardianUpgradeable.sol:GuardianUpgradeable",
            true // bypass upgrade safety checks
        );
        require(newImplementation.code.length > 0, "Guardian implementation deploy failed");
        vm.stopBroadcast();

        console.log("Guardian proxy", GUARDIAN_PROXY);
        console.log("Current implementation", currentImplementation);
        console.log("New implementation", newImplementation);
    }

    function _codeCheck() internal {
        require(GUARDIAN_PROXY.code.length > 0, "Guardian proxy not deployed");
        require(currentImplementation.code.length > 0, "Guardian proxy implementation is invalid");
    }
}
