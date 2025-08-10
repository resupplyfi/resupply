// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { console } from "forge-std/console.sol";
import { KeeperV1 } from "src/helpers/keepers/KeeperV1.sol";
import { TreasuryManagerUpgradeable } from "src/dao/operators/TreasuryManagerUpgradeable.sol";
import { GuardianUpgradeable } from "src/dao/operators/GuardianUpgradeable.sol";

contract DeployProxy is BaseAction {

    address public proxy;

    function run() public {
        vm.startBroadcast(vm.envUint("PK_RESUPPLY"));

        // Deploy guardian operator
        proxy = deployGuardianOperator();
        address owner = GuardianUpgradeable(proxy).owner();
        console.log("Proxy deployed at", proxy);
        console.log("Owner", owner);
        require(owner == Protocol.CORE, "Deployer is not the owner");

        // Deploy treasury manager operator
        proxy = deployTreasuryManagerOperator();
        owner = TreasuryManagerUpgradeable(proxy).owner();
        console.log("Proxy deployed at", proxy);
        console.log("Owner", owner);
        require(owner == Protocol.CORE, "Deployer is not the owner");

        // Deploy keeper
        proxy = deployKeeper();
        owner = KeeperV1(proxy).owner();
        console.log("Proxy deployed at", proxy);
        console.log("Owner", owner);
        require(owner == Protocol.DEPLOYER, "Deployer is not the owner");

        vm.stopBroadcast();
    }

    function deployGuardianOperator() public returns (address) {
        bytes memory initializerData = abi.encodeCall(GuardianUpgradeable.initialize, Protocol.DEPLOYER);
        return deployUUPSProxy(
            "GuardianUpgradeable.sol:GuardianUpgradeable", 
            initializerData, 
            true   // unsafeSkipAllChecks - set to false during deployment 
        );
    }

    function deployTreasuryManagerOperator() public returns (address) {
        bytes memory initializerData = abi.encodeCall(TreasuryManagerUpgradeable.initialize, Protocol.DEPLOYER);
        return deployUUPSProxy(
            "TreasuryManagerUpgradeable.sol:TreasuryManagerUpgradeable",
            initializerData,
            true   // unsafeSkipAllChecks - set to false during deployment 
        );
    }

    function deployKeeper() public returns (address) {
        bytes memory initializerData = abi.encodeCall(KeeperV1.initialize, Protocol.DEPLOYER);
        return deployUUPSProxy(
            "KeeperV1.sol:KeeperV1", 
            initializerData, 
            true   // unsafeSkipAllChecks - set to false during deployment 
        );
    }
}