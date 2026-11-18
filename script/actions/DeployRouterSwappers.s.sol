// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { Protocol } from "src/Constants.sol";
import { RouterSwapper } from "src/protocol/swappers/RouterSwapper.sol";
import { console } from "forge-std/console.sol";

contract DeployRouterSwappers is Script {
    address public constant LIFI_ROUTER = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
    address public constant ENSO_ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;

    function run() public returns (RouterSwapper ensoSwapper, RouterSwapper lifiSwapper) {
        vm.startBroadcast();
        ensoSwapper = new RouterSwapper(Protocol.CORE, ENSO_ROUTER, "Resupply Swapper: ENSO");
        lifiSwapper = new RouterSwapper(Protocol.CORE, LIFI_ROUTER, "Resupply Swapper: LI.FI");

        ensoSwapper.updateApprovals();
        lifiSwapper.updateApprovals();
        vm.stopBroadcast();

        console.log("ENSO swapper deployed at", address(ensoSwapper));
        console.log("LI.FI swapper deployed at", address(lifiSwapper));
        console.log("Router swapper approvals updated");
    }
}
