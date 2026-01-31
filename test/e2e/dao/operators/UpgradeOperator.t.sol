// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/e2e/Setup.sol";
import { Protocol } from "src/Constants.sol";
import { UpgradeOperator } from "src/dao/operators/UpgradeOperator.sol";
import { IUpgradeableOperator } from "src/interfaces/IUpgradeableOperator.sol";
import { RedemptionOperator } from "src/dao/operators/RedemptionOperator.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/Options.sol";

contract UpgradeOperatorTest is Setup {
    UpgradeOperator public upgradeOperator;
    address public proxy;
    address public implV1;
    address public implV2;

    function setUp() public override {
        super.setUp();

        bytes memory initializerData = abi.encodeCall(RedemptionOperator.initialize, new address[](0));
        Options memory options;
        options.unsafeSkipAllChecks = true;
        proxy = Upgrades.deployUUPSProxy(
            "RedemptionOperator.sol:RedemptionOperator",
            initializerData,
            options
        );
        implV1 = Upgrades.getImplementationAddress(proxy);
        implV2 = Upgrades.prepareUpgrade("RedemptionOperator.sol:RedemptionOperator", options);

        upgradeOperator = new UpgradeOperator(Protocol.CORE, Protocol.DEPLOYER);
        setOperatorPermission(address(upgradeOperator), proxy, IUpgradeableOperator.upgradeToAndCall.selector, true);
    }

    function test_UpgradeToAndCall() public {
        vm.prank(Protocol.DEPLOYER);
        upgradeOperator.upgradeToAndCall(proxy, implV2, "");

        address implAfter = Upgrades.getImplementationAddress(proxy);
        assertNotEq(implAfter, implV1);
        assertEq(implAfter, implV2);
    }

    function test_UpgradeToAndCall_NotOwner() public {
        vm.prank(address(1));
        vm.expectRevert("!authorized");
        upgradeOperator.upgradeToAndCall(proxy, implV2, "");
    }

    function test_SetManager() public {
        address newManager = address(0xBEEF);
        vm.prank(address(core));
        upgradeOperator.setManager(newManager);
        assertEq(upgradeOperator.manager(), newManager);
    }

    function test_SetManager_NotOwner() public {
        vm.prank(address(1));
        vm.expectRevert("!core");
        upgradeOperator.setManager(address(0xBEEF));
    }
}
