// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/integration/Setup.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/Options.sol";
import { KeeperV1 } from "src/helpers/keepers/KeeperV1.sol";
import { KeeperV2 } from "src/helpers/keepers/KeeperV2.sol";

contract KeeperTest is Setup {
    address proxy;
    address implV1;
    address implV2;

    function setUp() override public {
        bytes memory initializerData = abi.encodeCall(KeeperV1.initialize, address(this));
        Options memory options;
        options.unsafeSkipAllChecks = true;
        proxy = Upgrades.deployUUPSProxy(
            "KeeperV1.sol:KeeperV1",
            initializerData, // initializeer data
            options
        );
        implV1 = Upgrades.getImplementationAddress(proxy);
        implV2 = Upgrades.prepareUpgrade("KeeperV2.sol:KeeperV2", options);
    }

    function test_Upgrade() public {
        address implBefore = Upgrades.getImplementationAddress(proxy);
        assertNotEq(implBefore, address(0));
        assertEq(implBefore, implV1);

        KeeperV1(proxy).upgradeToAndCall(implV2, "");

        address implAfter = Upgrades.getImplementationAddress(proxy);
        assertNotEq(implAfter, address(0));
        assertNotEq(implAfter, implV1);
        assertEq(implAfter, implV2);
    }

    function test_UpgradeAuth() public {
        assertEq(KeeperV1(proxy).owner(), address(this));

        vm.prank(address(1));
        vm.expectRevert("!owner");
        KeeperV1(proxy).upgradeToAndCall(implV2, "");

        // should succeed
        KeeperV1(proxy).upgradeToAndCall(implV2, "");
    }

    function test_Reinitialize() public {
        vm.expectRevert(bytes("InvalidInitialization()"));
        KeeperV1(proxy).initialize(address(1));

        KeeperV1(proxy).upgradeToAndCall(implV2, "");

        // V2 contains an initializer but it's a no-op. Nonetheless should still revert thanks to the modifier.
        vm.expectRevert(bytes("InvalidInitialization()"));
        KeeperV2(proxy).initialize();
    }
}