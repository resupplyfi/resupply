// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console2 } from "forge-std/console2.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { Setup } from "test/Setup.sol";

contract RegistryTest is Setup {

    function setUp() public override {
        super.setUp();
    }

    function test_SetAddress() public {
        vm.startPrank(address(core));
        string memory key = "test";
        bytes32 keyHash = keccak256(abi.encodePacked(key));
        registry.setAddress(key, address(this));
        assertEq(registry.getAddress(key), address(this));
        address addr = registry.getAddress(key);
        assertEq(addr, address(this));
        assertEq(registry.hashToKey(keyHash), key);
        console2.log("key", key);
        console2.logBytes32(keyHash);
        console2.log('Key', registry.hashToKey(keyHash));
        vm.stopPrank();
    }

    function test_GetAddress() public {
        vm.startPrank(address(core));
        registry.setAddress("test", address(this));
        vm.expectRevert(
            abi.encodeWithSelector(ResupplyRegistry.ProtectedKey.selector, "STAKER")
        );
        registry.setAddress("STAKER", address(staker));
        registry.setAddress("STABLECOIN2", address(stablecoin));
        registry.setAddress("REDEMPTION_HANDLER2", address(redemptionHandler));
        registry.setAddress("INSURANCE_POOL2", address(insurancePool));
        assertEq(registry.getAddress("test"), address(this));
        string[] memory keys = registry.getAllKeys();
        for (uint i = 0; i < keys.length; i++) {
            console2.log("Key", i, keys[i], registry.getAddress(keys[i]));
        }
        vm.stopPrank();
    }
     
    function test_AccessControl() public {
        vm.expectRevert("!core");
        registry.setAddress("test", address(this));
        vm.expectRevert("!core");
        registry.setStaker(address(this));
        vm.expectRevert("!core");
        registry.setRedemptionHandler(address(this));
        vm.expectRevert("!core");
        registry.setInsurancePool(address(this));
    }

    function test_CannotAddProtectedKey() public {
        vm.startPrank(address(core));
        string[] memory protectedKeys = registry.getProtectedKeys();
        require(protectedKeys.length > 0, "No protected keys found");
        for (uint i = 0; i < protectedKeys.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(ResupplyRegistry.ProtectedKey.selector, protectedKeys[i])
            );
            registry.setAddress(protectedKeys[i], address(this));
        }
        vm.stopPrank();
    }
}
