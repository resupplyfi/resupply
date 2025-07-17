// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { Setup } from "test/integration/Setup.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { UnsafeUpgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { KeeperV1 } from "src/helpers/keepers/KeeperV1.sol";
import { KeeperV2 } from "src/helpers/keepers/KeeperV2.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract KeeperTest is Setup {
    address proxy;
    address implV1;
    address implV2;

    function setUp() override public {
        // Deploy impl
        implV1 = address(new KeeperV1());

        // Deploy proxy
        bytes memory init = abi.encodeCall(KeeperV1.initialize, ());
        proxy = address(new TransparentUpgradeableProxy(
            implV1,
            address(this),
            init
        ));
    }

    function test_Upgrade() public {
        address implBefore = Upgrades.getImplementationAddress(proxy);
        assertNotEq(implBefore, address(0));
        assertEq(implBefore, implV1);

        // Pre-upgrade things

        // Upgrade
        // Options memory options;
        // options.unsafeSkipAllChecks = true;
        implV2 = address(new KeeperV2());
        UnsafeUpgrades.upgradeProxy(proxy, implV2, "", address(this));

        // Post-upgrade things
        address implAfter = Upgrades.getImplementationAddress(proxy);
        assertNotEq(implAfter, address(0));
        assertNotEq(implAfter, implV1);
        assertEq(implAfter, implV2);
    }
}