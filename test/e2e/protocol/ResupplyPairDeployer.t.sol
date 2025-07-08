// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Protocol, Mainnet} from "src/Constants.sol";
import {Test} from "forge-std/Test.sol";
import {ResupplyPairDeployer} from "src/protocol/ResupplyPairDeployer.sol";
import {Setup} from "test/e2e/Setup.sol";
import {console2} from "forge-std/console2.sol";
import {ResupplyPair} from "src/protocol/ResupplyPair.sol";

contract ResupplyPairDeployerTest is Setup {
    address public curveLendCollat = Mainnet.CURVELEND_SFRXUSD_CRVUSD;
    
    function setUp() public override {
        super.setUp();
    }

    function test_SetAndGetValidProtocolData() public {
        // Test setting valid protocol data
        vm.prank(address(core));
        uint256 platformId = deployer.addSupportedProtocol("TestProtocol", bytes4(0), bytes4(0));
        
        // Verify the data was set correctly
        string memory name = deployer.platformNameById(platformId);
        assertEq(name, "TestProtocol");
    }

    function test_SetInvalidProtocolData() public {
        string memory longName = "ThisIsAnExtremelyLongProtocolNameThatShouldDefinitelyExceedAnyReasonableLimit";
        vm.expectRevert(abi.encodeWithSelector(ResupplyPairDeployer.ProtocolNameTooLong.selector));
        vm.prank(address(core));
        deployer.addSupportedProtocol(longName, bytes4(0), bytes4(0));
    }

    function test_ValidGetName() public {
        string memory actualName;
        vm.expectRevert(abi.encodeWithSelector(ResupplyPairDeployer.ProtocolNotFound.selector));
        (actualName, , ) = deployer.getNextName(12, curveLendCollat);
        (actualName, , ) = deployer.getNextName(0, curveLendCollat);
        string memory expectedName = "Resupply Pair (CurveLend: crvUSD/sfrxUSD) - 1";
        assertEq(actualName, expectedName);
    }

    function test_updateProtocolData() public {
        vm.prank(address(core));
        uint256 protocolId = deployer.addSupportedProtocol("TestProtocol", bytes4(0), bytes4(0));
        vm.prank(address(core));
        deployer.updateSupportedProtocol(protocolId, "TestProtocol2", bytes4(0), bytes4(0));
    }

    function test_deployLendingPair() public {
        ResupplyPair pair = _deployPairAs(
            address(core),
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Mainnet.CONVEX_BOOSTER,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        assertGt(pair.protocolRedemptionFee(), 0);
        assertGt(bytes(pair.name()).length, 5);
        console2.log("Name: ", pair.name());
        console2.log("Redemption Fee: ", pair.protocolRedemptionFee());
    }

    function test_AtomicRegisterOnDeploy() public {
        ResupplyPair pair = _deployPairAs(
            address(core),
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Mainnet.CONVEX_BOOSTER,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        assertGt(address(pair).code.length, 0);
        assertEq(registry.pairsByName(pair.name()), address(pair));
    }

    function test_predictPairAddress() public {
        address pairAddress = _predictPairAddress(
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Mainnet.CONVEX_BOOSTER,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        console2.log("Predicted Pair Address: ", pairAddress);
        ResupplyPair pair = _deployPairAs(
            address(core),
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Mainnet.CONVEX_BOOSTER,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        assertEq(pairAddress, address(pair));
    }

    function test_DeployPermissions(address _deployer) public {
        ResupplyPair pair;
        vm.expectRevert("!core");
        pair = _deployPairAs(
            _deployer,
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Mainnet.CONVEX_BOOSTER,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );

        pair = _deployPairAs(
            address(core),
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Mainnet.CONVEX_BOOSTER,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        assertNotEq(address(pair), address(0));
    }

    function _deployPairAs(address _deployer, uint256 _protocolId, address _collateral, address _staking, uint256 _stakingId) internal returns(ResupplyPair){
        vm.prank(_deployer);
        address _pairAddress = deployer.deploy(
            _protocolId,
            abi.encode(
                _collateral,
                address(oracle),
                address(rateCalculator),
                DEFAULT_MAX_LTV, //max ltv 75%
                DEFAULT_BORROW_LIMIT,
                DEFAULT_LIQ_FEE,
                DEFAULT_MINT_FEE,
                DEFAULT_PROTOCOL_REDEMPTION_FEE
            ),
            _staking,
            _stakingId
        );
        return ResupplyPair(_pairAddress);
    }

    function _predictPairAddress(uint256 _protocolId, address _collateral, address _staking, uint256 _stakingId) internal view returns(address){
        address _pairAddress = deployer.predictPairAddress(
            _protocolId,
            abi.encode(
                _collateral,
                address(oracle),
                address(rateCalculator),
                DEFAULT_MAX_LTV, //max ltv 75%
                DEFAULT_BORROW_LIMIT,
                DEFAULT_LIQ_FEE,
                DEFAULT_MINT_FEE,
                DEFAULT_PROTOCOL_REDEMPTION_FEE
            ),
            _staking,
            _stakingId
        );
        return _pairAddress;
    }
}