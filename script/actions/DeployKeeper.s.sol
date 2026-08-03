// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Keeper } from "src/helpers/keepers/Keeper.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { console } from "forge-std/console.sol";

contract DeployKeeper is BaseAction {
    uint256 constant MIN_PROFIT = 100e18;

    function run() public returns (address keeper) {
        address[] memory operators = new address[](1);
        operators[0] = 0x21862cA8d044c104ac9EB728c86Bc38B8625BeCD;

        address owner = keeperOwner();

        vm.startBroadcast();
        keeper = address(new Keeper(owner, operators, MIN_PROFIT));
        vm.stopBroadcast();

        console.log("keeper deployed at", keeper);
    }

    function keeperOwner() internal returns (address owner) {
        try vm.envAddress("KEEPER_OWNER") returns (address configuredOwner) {
            owner = configuredOwner;
        } catch {
            owner = Protocol.DEPLOYER;
        }
    }
}
