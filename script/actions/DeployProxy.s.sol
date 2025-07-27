// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { console } from "forge-std/console.sol";
import { KeeperV1 } from "src/helpers/keepers/KeeperV1.sol";

contract DeployProxy is BaseAction {

    address public proxy;

    function run() public {
        proxy = deployProxy();
        console.log("Proxy deployed at", proxy);
        console.log("Owner", KeeperV1(proxy).owner());
        require(KeeperV1(proxy).owner() == Protocol.DEPLOYER, "Deployer is not the owner");
    }

    function deployProxy() public returns (address) {
        bytes memory initializerData = abi.encodeCall(KeeperV1.initialize, Protocol.DEPLOYER);
        return deployUUPSProxy("KeeperV1.sol:KeeperV1", initializerData, true);
    }

    function upgradeProxy(address _proxy) public {
        upgradeProxy(_proxy, "KeeperV2.sol:KeeperV2", "", true);
    }
}