// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Keeper } from "src/helpers/keepers/Keeper.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";

contract DeployKeeper is BaseAction {
    uint256 constant MIN_PROFIT = 100e18;

    function run() public {
        address[] memory ops = new address[](1);
        ops[0] = 0x21862cA8d044c104ac9EB728c86Bc38B8625BeCD;

        uint256 pk = loadPrivateKey();
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);
        new Keeper(deployer, ops, MIN_PROFIT);
        vm.stopBroadcast();
    }
}