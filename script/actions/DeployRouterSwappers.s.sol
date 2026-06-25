// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { RouterSwapper } from "src/protocol/swappers/RouterSwapper.sol";
import { console } from "forge-std/console.sol";

contract DeployRouterSwappers is BaseAction {
    address public constant ODOS_ROUTER = 0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05;
    address public constant LIFI_ROUTER = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
    address public constant ENSO_ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;

    function run() public {
        vm.startBroadcast();
        RouterSwapper odosSwapper = new RouterSwapper(Protocol.CORE, ODOS_ROUTER, "Resupply Swapper: ODOS");
        RouterSwapper lifiSwapper = new RouterSwapper(Protocol.CORE, LIFI_ROUTER, "Resupply Swapper: LI.FI");
        RouterSwapper ensoSwapper = new RouterSwapper(Protocol.CORE, ENSO_ROUTER, "Resupply Swapper: ENSO");

        odosSwapper.updateApprovals();
        lifiSwapper.updateApprovals();
        ensoSwapper.updateApprovals();
        vm.stopBroadcast();

        console.log("ODOS swapper deployed at", address(odosSwapper));
        console.log("LI.FI swapper deployed at", address(lifiSwapper));
        console.log("ENSO swapper deployed at", address(ensoSwapper));
        console.log("Router swapper approvals updated");
    }
}
