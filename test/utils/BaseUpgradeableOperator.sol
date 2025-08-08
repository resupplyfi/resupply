// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { Protocol } from "src/Constants.sol";
import { Upgrades, UnsafeUpgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/Options.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IProxy {
    function owner() external view returns (address);
}

abstract contract BaseUpgradeableOperatorTest is Test {
    address public constant CORE = 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d;
    address public proxy;
    address public implV1;
    address public implV2;

    // Abstract functions that child contracts must implement
    function initialize() internal virtual;
    function getContractNameV1() internal view virtual returns (string memory);
    function getContractNameV2() internal view virtual returns (string memory);
    function getInitializerData() internal view virtual returns (bytes memory);
    
    // Optional overrides for custom behavior
    function getUpgradeOptions() internal view virtual returns (Options memory) {
        Options memory options;
        options.unsafeSkipAllChecks = true;
        return options;
    }

    function deployProxyAndImplementation() public returns (address, address) {        
        bytes memory initializerData = getInitializerData();
        Options memory options = getUpgradeOptions();
        
        proxy = Upgrades.deployUUPSProxy(
            getContractNameV1(),
            initializerData,
            options
        );
        implV1 = Upgrades.getImplementationAddress(proxy);
        implV2 = Upgrades.prepareUpgrade(getContractNameV2(), options);
        return (proxy, implV2);
    }

    function test_Upgrade() public {
        address implBefore = Upgrades.getImplementationAddress(proxy);
        assertNotEq(implBefore, address(0));
        assertEq(implBefore, implV1);

        // Upgrade to V2. Pass empty data to avoid reinitialization error.
        vm.prank(CORE);
        UUPSUpgradeable(proxy).upgradeToAndCall(implV2, "");

        address implAfter = Upgrades.getImplementationAddress(proxy);
        assertNotEq(implAfter, address(0));
        assertNotEq(implAfter, implV1);
        assertEq(implAfter, implV2);
    }

    function test_UpgradeAuth() public {
        address owner = IProxy(proxy).owner();
        assertEq(owner, CORE);

        vm.prank(address(1));
        vm.expectRevert("!owner");
        UUPSUpgradeable(proxy).upgradeToAndCall(implV2, "");

        // Should succeed when called by owner. Pass empty data to avoid reinitialization error.
        vm.prank(CORE);
        UUPSUpgradeable(proxy).upgradeToAndCall(implV2, "");
    }

    function test_Reinitialize() public {
        // V1 should not be reinitializable
        vm.expectRevert(bytes("InvalidInitialization()"));
        initialize();
    
        // V2 should also not be reinitializable
        vm.expectRevert(bytes("InvalidInitialization()"));
        initialize();
    }
}