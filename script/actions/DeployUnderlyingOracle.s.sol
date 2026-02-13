// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { UnderlyingOracle } from "src/protocol/UnderlyingOracle.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";

contract DeployUnderlyingOracle is BaseAction {

    function run() public {
        uint256 pk = loadPrivateKey();
        vm.startBroadcast(pk);
        new UnderlyingOracle("Underlying Token Oracle v2");
        vm.stopBroadcast();
    }
}
