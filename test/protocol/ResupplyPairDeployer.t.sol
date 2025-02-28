// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;
import {Test} from "forge-std/Test.sol";
import {ResupplyPairDeployer} from "src/protocol/ResupplyPairDeployer.sol";
import {Setup} from "test/Setup.sol";
import {console2} from "forge-std/console2.sol";
import {ResupplyPair} from "src/protocol/ResupplyPair.sol";

contract ResupplyPairDeployerTest is Setup {
    ResupplyPairDeployer public resupplyPairDeployer;
    address public curveLendCollat = Constants.Mainnet.CURVELEND_SFRXUSD_CRVUSD;
    // address public fraxlendCollat = Constants.Mainnet.FRAXLEND_SFRXETH_FRAX;
    
    function setUp() public override {
        super.setUp();
        resupplyPairDeployer = new ResupplyPairDeployer(address(core), address(registry), address(govToken), address(core));
        vm.startPrank(address(core));
        resupplyPairDeployer.addSupportedProtocol(
            "CurveLend",
            bytes4(keccak256("asset()")),           // borrowLookupSig
            bytes4(keccak256("collateral_token()")) // collateralLookupSig
        );
        resupplyPairDeployer.addSupportedProtocol(
            "Fraxlend",
            bytes4(keccak256("asset()")),           // borrowLookupSig
            bytes4(keccak256("collateralContract()")) // collateralLookupSig
        );
        vm.stopPrank();
    }

    function test_SetAndGetValidProtocolData() public {
        // Test setting valid protocol data
        vm.prank(address(core));
        uint256 platformId = resupplyPairDeployer.addSupportedProtocol("TestProtocol", bytes4(0), bytes4(0));
        
        // Verify the data was set correctly
        string memory name = resupplyPairDeployer.platformNameById(platformId);
        assertEq(name, "TestProtocol");
    }

    function test_SetInvalidProtocolData() public {
        string memory longName = "ThisIsAnExtremelyLongProtocolNameThatShouldDefinitelyExceedAnyReasonableLimit";
        vm.expectRevert(abi.encodeWithSelector(ResupplyPairDeployer.ProtocolNameTooLong.selector));
        vm.prank(address(core));
        resupplyPairDeployer.addSupportedProtocol(longName, bytes4(0), bytes4(0));
    }

    function test_ValidGetName() public {
        string memory actualName;
        vm.expectRevert(abi.encodeWithSelector(ResupplyPairDeployer.ProtocolNotFound.selector));
        (actualName, , ) = resupplyPairDeployer.getNextName(12, curveLendCollat);
        (actualName, , ) = resupplyPairDeployer.getNextName(0, curveLendCollat);
        string memory expectedName = "Resupply Pair (CurveLend: crvUSD/sfrxUSD) - 1";
        assertEq(actualName, expectedName);
    }

    function test_updateProtocolData() public {
        vm.prank(address(core));
        uint256 protocolId = resupplyPairDeployer.addSupportedProtocol("TestProtocol", bytes4(0), bytes4(0));
        vm.prank(address(core));
        resupplyPairDeployer.updateSupportedProtocol(protocolId, "TestProtocol2", bytes4(0), bytes4(0));
    }

    function test_deployLendingPair() public {
        ResupplyPair pair = deployLendingPair(
            0,
            Constants.Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Constants.Mainnet.CONVEX_BOOSTER,
            uint256(Constants.Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        assertGt(pair.protocolRedemptionFee(), 0);
        assertGt(bytes(pair.name()).length, 5);
        console2.log("Name: ", pair.name());
        console2.log("Redemption Fee: ", pair.protocolRedemptionFee());
    }
}