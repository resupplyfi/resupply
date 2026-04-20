pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { SwapperLifi } from "src/protocol/SwapperLifi.sol";
import { console } from "forge-std/console.sol";

contract DeployLifiSwapper is BaseAction {
    function run() public {
        vm.startBroadcast(loadPrivateKey());
        SwapperLifi swapper = new SwapperLifi(Protocol.CORE);
        swapper.updateApprovals();
        vm.stopBroadcast();

        console.log("LI.FI swapper deployed at", address(swapper));
        console.log("LI.FI swapper approvals updated");
    }
}
