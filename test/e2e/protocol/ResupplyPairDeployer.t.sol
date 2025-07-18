// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Protocol, Mainnet, DeploymentConfig} from "src/Constants.sol";
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
        uint256 platformId = deployer.addSupportedProtocol("TestProtocol", 1e18, 1e17, bytes4(0), bytes4(0));
        
        // Verify the data was set correctly
        string memory name = deployer.platformNameById(platformId);
        assertEq(name, "TestProtocol");
    }

    function test_SetInvalidProtocolData() public {
        string memory longName = "ThisIsAnExtremelyLongProtocolNameThatShouldDefinitelyExceedAnyReasonableLimit";
        vm.expectRevert(abi.encodeWithSelector(ResupplyPairDeployer.ProtocolNameTooLong.selector));
        vm.prank(address(core));
        deployer.addSupportedProtocol(longName, 1e18, 1e17, bytes4(0), bytes4(0));
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
        uint256 protocolId = deployer.addSupportedProtocol(
            "TestProtocol", 
            1e18,
            1e17,
            bytes4(0), 
            bytes4(0)
        );
        vm.prank(address(core));
        deployer.updateSupportedProtocol(
            protocolId, 
            "TestProtocol2", 
            1e18,
            1e17,
            bytes4(0), 
            bytes4(0)
        );
    }

    function test_deployLendingPair() public {
        ResupplyPair pair = deployLendingPairAs(
            address(core),
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        assertGt(pair.protocolRedemptionFee(), 0);
        assertGt(bytes(pair.name()).length, 5);
        console2.log("Name: ", pair.name());
        console2.log("Redemption Fee: ", pair.protocolRedemptionFee());
    }

    function test_AtomicRegisterOnDeploy() public {
        ResupplyPair pair = deployLendingPairAs(
            address(core),
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
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
        ResupplyPair pair = deployLendingPairAs(
            address(core),
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        assertEq(pairAddress, address(pair));
    }

    function test_DeployPermissions(address _deployer) public {
        ResupplyPair pair;
        vm.expectRevert(abi.encodeWithSelector(ResupplyPairDeployer.WhitelistedDeployersOnly.selector));
        pair = deployLendingPairAs(
            _deployer,
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );

        pair = deployLendingPairAs(
            address(core),
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        assertNotEq(address(pair), address(0));
    }

    function test_DeployInfoSet() public {
        vm.expectRevert(abi.encodeWithSelector(
            ResupplyPairDeployer.InvalidBorrowOrCollateralTokenLookup.selector
        ));
        ResupplyPair pair = deployLendingPairAs(
            address(core),
            0,
            Mainnet.FRAXLEND_SFRXETH_FRXUSD,
            uint256(0)
        );

        pair = deployLendingPairAs(
            address(core),
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        (uint40 protocolId, uint40 deployTime) = deployer.deployInfo(address(pair));
        assertEq(protocolId, 0);
        assertEq(deployTime, uint40(block.timestamp));

        pair = deployLendingPairAs(
            address(core),
            1,
            Mainnet.FRAXLEND_SFRXETH_FRXUSD,
            uint256(0)
        );
        (protocolId, deployTime) = deployer.deployInfo(address(pair));
        assertEq(protocolId, 1);
        assertEq(deployTime, uint40(block.timestamp));
    }

    function _predictPairAddress(uint256 _protocolId, address _collateral, address _staking, uint256 _stakingId) internal view returns(address){
        address _pairAddress = deployer.predictPairAddress(
            _protocolId,
            abi.encode(
                _collateral,
                address(oracle),
                address(rateCalculator),
                DeploymentConfig.DEFAULT_MAX_LTV, //max ltv 75%
                DeploymentConfig.DEFAULT_BORROW_LIMIT,
                DeploymentConfig.DEFAULT_LIQ_FEE,
                DeploymentConfig.DEFAULT_MINT_FEE,
                DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
            ),
            _staking,
            _stakingId
        );
        return _pairAddress;
    }

    function test_SetDefaultConfigData() public {
        address newOracle = address(0x123);
        address newRateCalculator = address(0x456);
        uint256 newMaxLTV = 8000; // 80%
        uint256 newBorrowLimit = 50_000_000e18;
        uint256 newLiquidationFee = 500; // 0.5%
        uint256 newMintFee = 100; // 0.1%
        uint256 newProtocolRedemptionFee = 300; // 0.3%

        vm.prank(address(core));
        deployer.setDefaultConfigData(
            newOracle,
            newRateCalculator,
            newMaxLTV,
            newBorrowLimit,
            newLiquidationFee,
            newMintFee,
            newProtocolRedemptionFee
        );

        assertEq(deployer.defaultConfigData().oracle, newOracle);
        assertEq(deployer.defaultConfigData().rateCalculator, newRateCalculator);
        assertEq(deployer.defaultConfigData().maxLTV, newMaxLTV);
        assertEq(deployer.defaultConfigData().initialBorrowLimit, newBorrowLimit);
        assertEq(deployer.defaultConfigData().liquidationFee, newLiquidationFee);
        assertEq(deployer.defaultConfigData().mintFee, newMintFee);
        assertEq(deployer.defaultConfigData().protocolRedemptionFee, newProtocolRedemptionFee);
    }

    function test_SetInvalidDefaultConfigData() public {
        vm.expectRevert(abi.encodeWithSelector(ResupplyPairDeployer.InvalidConfigData.selector));
        vm.prank(address(core));
        deployer.setDefaultConfigData(
            address(0), // invalid oracle
            address(rateCalculator),
            8000,
            50_000_000e18,
            500,
            100,
            300
        );

        vm.expectRevert(abi.encodeWithSelector(ResupplyPairDeployer.InvalidConfigData.selector));
        vm.prank(address(core));
        deployer.setDefaultConfigData(
            address(oracle),
            address(0), // invalid rate calculator
            8000,
            50_000_000e18,
            500,
            100,
            300
        );
    }

    function test_DeployWithDefaults() public {
        // Deploy using the overloaded function with defaults
        vm.prank(address(core));
        address pairAddress = deployer.deploy(
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Mainnet.CONVEX_BOOSTER,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );

        ResupplyPair pair = ResupplyPair(pairAddress);
        assertGt(address(pair).code.length, 0);
        assertEq(address(pair.collateral()), Mainnet.CURVELEND_SFRXUSD_CRVUSD);
        
        // Verify the pair uses default config values
        (address oracle,,) = pair.exchangeRateInfo();
        assertEq(oracle, deployer.defaultConfigData().oracle);
        assertEq(address(pair.rateCalculator()), deployer.defaultConfigData().rateCalculator);
        assertEq(pair.maxLTV(), deployer.defaultConfigData().maxLTV);
        assertEq(pair.borrowLimit(), deployer.defaultConfigData().initialBorrowLimit);
        assertEq(pair.liquidationFee(), deployer.defaultConfigData().liquidationFee);
        assertEq(pair.mintFee(), deployer.defaultConfigData().mintFee);
        assertEq(pair.protocolRedemptionFee(), deployer.defaultConfigData().protocolRedemptionFee);
    }

    function test_PredictPairAddressWithDefaults() public {
        address predictedAddress = deployer.predictPairAddress(
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Mainnet.CONVEX_BOOSTER,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );

        // Deploy the pair and verify the address matches
        vm.prank(address(core));
        address actualAddress = deployer.deploy(
            0,
            Mainnet.CURVELEND_SFRXUSD_CRVUSD,
            Mainnet.CONVEX_BOOSTER,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );

        assertEq(predictedAddress, actualAddress);
    }
}