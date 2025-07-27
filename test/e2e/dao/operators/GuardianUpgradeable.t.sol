// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "forge-std/console.sol";
import { Protocol } from "src/Constants.sol";
import { GuardianUpgradeable } from "src/dao/operators/GuardianUpgradeable.sol";
import { Upgrades, UnsafeUpgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/Options.sol";
import { BaseUpgradeableOperatorTest } from "test/utils/BaseUpgradeableOperator.sol";
import { Setup } from "test/e2e/Setup.sol";

contract GuardianUpgradeableTest is Setup, BaseUpgradeableOperatorTest {
    address public guardian = Protocol.DEPLOYER;

    function setUp() public override {
        super.setUp();
        deployProxyAndImplementation();
    }

    // Implement abstract functions from BaseUpgradeableOperatorTest
    function initialize() internal override {GuardianUpgradeable(proxy).initialize(guardian);}
    function getContractNameV1() internal view override returns (string memory) {return "GuardianUpgradeable.sol:GuardianUpgradeable";}
    function getContractNameV2() internal view override returns (string memory) {return "GuardianUpgradeable.sol:GuardianUpgradeable";}
    function getInitializerData() internal view override returns (bytes memory) {return abi.encodeCall(GuardianUpgradeable.initialize, guardian);}

    function test_GuardianSet() public {
        assertEq(GuardianUpgradeable(proxy).guardian(), guardian);
    }

    function test_GuardianSet_NotOwner() public {
        vm.prank(address(1));
        vm.expectRevert("!owner");
        GuardianUpgradeable(proxy).setGuardian(address(1));
    }
}