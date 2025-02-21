// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PairNameHelper} from "src/protocol/PairNameHelper.sol";
import {Setup} from "test/Setup.sol";

contract NameHelperTest is Setup {
    PairNameHelper public pairNameHelper;
    address public curveLendCollat;
    address public fraxlendCollat;
    
    function setUp() public override {
        super.setUp();
        pairNameHelper = new PairNameHelper(address(core), address(registry));
        curveLendCollat = 0xd0c183C9339e73D7c9146D48E1111d1FBEe2D6f9; // crvUSD/sFRAX
        fraxlendCollat = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15; // sFRAX/FRAX
        vm.startPrank(address(core));
        pairNameHelper.addProtocolData(
            "CurveLend",
            bytes4(keccak256("asset()")),           // borrowLookupSig
            bytes4(keccak256("collateral_token()")) // collateralLookupSig
        );
        pairNameHelper.addProtocolData(
            "Fraxlend",
            bytes4(keccak256("asset()")),           // borrowLookupSig
            bytes4(keccak256("collateralContract()")) // collateralLookupSig
        );
        vm.stopPrank();
    }

    function test_SetAndGetValidProtocolData() public {
        // Test setting valid protocol data
        vm.prank(address(core));
        uint256 platformId = pairNameHelper.addProtocolData("TestProtocol", bytes4(0), bytes4(0));
        
        // Verify the data was set correctly
        string memory name = pairNameHelper.platformNameById(platformId);
        assertEq(name, "TestProtocol");
    }

    function test_SetInvalidProtocolData() public {
        // Test too long name (assuming there's a reasonable max length)
        string memory longName = "ThisIsAnExtremelyLongProtocolNameThatShouldDefinitelyExceedAnyReasonableLimit";
        vm.expectRevert(abi.encodeWithSelector(PairNameHelper.ProtocolNameTooLong.selector));
        vm.prank(address(core));
        pairNameHelper.addProtocolData(longName, bytes4(0), bytes4(0));
    }

    function test_ValidGetName() public {
        // Set protocol data
        string memory actualName;
        vm.expectRevert(abi.encodeWithSelector(PairNameHelper.ProtocolNotFound.selector));
        actualName = pairNameHelper.getNextName(12, curveLendCollat);
        actualName = pairNameHelper.getNextName(0, curveLendCollat);
        // string memory expectedName = "Resupply Pair (TestProtocol) - 1";
        // assertEq(actualName, expectedName);
    }

    function test_updateProtocolData() public {
        vm.prank(address(core));
        uint256 platformId = pairNameHelper.addProtocolData("TestProtocol", bytes4(0), bytes4(0));
        vm.prank(address(core));
        pairNameHelper.updateProtocolData(platformId, "TestProtocol2", bytes4(0), bytes4(0));
    }
}