// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Protocol, Mainnet, DeploymentConfig} from "src/Constants.sol";
import {Test} from "forge-std/Test.sol";
import {ResupplyPairDeployer} from "src/protocol/ResupplyPairDeployer.sol";
import {Setup} from "test/integration/Setup.sol";
import {console2} from "forge-std/console2.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ResupplyPair} from "src/protocol/ResupplyPair.sol";
import {IResupplyPair} from "src/interfaces/IResupplyPair.sol";
import {IResupplyPairDeployer} from "src/interfaces/IResupplyPairDeployer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IAuthHook} from "src/interfaces/IAuthHook.sol";
import {IResupplyRegistry} from "src/interfaces/IResupplyRegistry.sol";
import {ICurveLendingVault} from "src/interfaces/curve/ICurveLendingVault.sol";
import {DeployInfo} from "test/utils/DeployInfo.sol";

contract ResupplyPairDeployerTest is Setup {
    using Strings for uint256;
    address public curveLendCollat = Mainnet.CURVELEND_SFRXUSD_CRVUSD;
    IResupplyPairDeployer public originalDeployer;
    
    function setUp() public override {
        super.setUp();
        originalDeployer = deployer;
        vm.prank(address(core));
        registry.setAddress("PAIR_DEPLOYER", address(deployer));
        (
            address[] memory previouslyDeployedPairs, 
            ResupplyPairDeployer.DeployInfo[] memory previouslyDeployedPairsInfo
        ) = DeployInfo.getDeployInfo();
        deployer = IResupplyPairDeployer(address(new ResupplyPairDeployer(
            address(core),
            address(registry),
            address(govToken),
            address(deployer),
            ResupplyPairDeployer.ConfigData({
                oracle: address(oracle),
                rateCalculator: address(rateCalculator),
                maxLTV: DeploymentConfig.DEFAULT_MAX_LTV,
                initialBorrowLimit: DeploymentConfig.DEFAULT_BORROW_LIMIT,
                liquidationFee: DeploymentConfig.DEFAULT_LIQ_FEE,
                mintFee: DeploymentConfig.DEFAULT_MINT_FEE,
                protocolRedemptionFee: DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
            }),
            previouslyDeployedPairs,
            previouslyDeployedPairsInfo
        )));
        vm.prank(address(core));
        deployer.setCreationCode(type(ResupplyPair).creationCode);
        deal(address(Mainnet.CRVUSD_ERC20), address(deployer), 100e18);
        deal(address(Mainnet.FRXUSD_ERC20), address(deployer), 100e18);
    }

    function test_StateDoesntMigrate() public {
        deployer = IResupplyPairDeployer(address(new ResupplyPairDeployer(
            address(core),
            address(registry),
            address(govToken),
            address(deployer),
            ResupplyPairDeployer.ConfigData({
                oracle: address(oracle),
                rateCalculator: address(rateCalculator),
                maxLTV: DeploymentConfig.DEFAULT_MAX_LTV,
                initialBorrowLimit: DeploymentConfig.DEFAULT_BORROW_LIMIT,
                liquidationFee: DeploymentConfig.DEFAULT_LIQ_FEE,
                mintFee: DeploymentConfig.DEFAULT_MINT_FEE,
                protocolRedemptionFee: DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
            }),
            new address[](0),
            new ResupplyPairDeployer.DeployInfo[](0)
        )));
        address[] memory pairs = registry.getAllPairAddresses();
        for (uint256 i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            (uint40 protocolId, uint40 deployTime) = deployer.deployInfo(_pair);
            assertEq(protocolId, 0);
            assertEq(deployTime, 0);
        }
    }

    function test_StateMigrated() public {
        // Test that supported protocols were migrated
        assertEq(deployer.supportedProtocolsLength(), 2);
        assertEq(deployer.platformNameById(0), "CurveLend");
        assertEq(deployer.platformNameById(1), "Fraxlend");

        // Test that existing pairs are accessible
        address[] memory pairs = registry.getAllPairAddresses();
        assertGt(pairs.length, 0);
        
        // Test that all existing pairs have their collateral IDs migrated
        address _borrowToken;
        address _collateralToken;
        for (uint256 i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            IResupplyPair pair = IResupplyPair(_pair);
            address _collateral = pair.collateral();
            uint256 _protocolId = getProtocolId(_collateral);
            (uint40 protocolId, uint40 deployTime) = deployer.deployInfo(_pair);
            assertEq(protocolId, _protocolId);
            assertGt(deployTime, 0);
            // Verify that the collateral ID exists (should be > 0 for existing pairs)
            (_borrowToken, _collateralToken) = deployer.getBorrowAndCollateralTokens(_protocolId, _collateral);
            uint256 collateralId = deployer.collateralId(_protocolId, _borrowToken, _collateralToken);
            assertGt(collateralId, 0, "Collateral ID should be migrated for existing pair");
            console2.log("Pair", i, ":", _pair);
            console2.log("  Protocol ID:", _protocolId);
            console2.log("  Collateral:", _collateral);
            console2.log("  Borrow Token:", _borrowToken);
            console2.log("  Collateral Token:", _collateralToken);
            console2.log("  Collateral ID:", collateralId);
        }
    }

    function getProtocolId(address _collateral) internal view returns(uint256){
        for (uint256 k = 0; k < deployer.supportedProtocolsLength(); k++) {
            (address _borrowToken, address _collateralToken) = deployer.getBorrowAndCollateralTokens(k, _collateral);
            if(_borrowToken != address(0) && _collateralToken != address(0)) {
                return k;
            }
        }
        revert("Protocol not found");
    }



    function test_NewPairIncrementsIdProperly() public {
        // Get an existing pair to use as reference
        address[] memory pairs = registry.getAllPairAddresses();
        require(pairs.length > 0, "No existing pairs found");
        
        IResupplyPair existingPair = IResupplyPair(pairs[0]);
        address _collateral = existingPair.collateral();
        uint256 _protocolId = getProtocolId(_collateral);
        // Get current collateral ID for this collateral
        (address _borrowToken, address _collateralToken) = deployer.getBorrowAndCollateralTokens(_protocolId, _collateral);
        uint256 currentCollateralId = deployer.collateralId(_protocolId, _borrowToken, _collateralToken);
        
        console2.log("Current collateral ID:", currentCollateralId);
        
        // Deploy a new pair with the same collateral
        ResupplyPair newPair = deployLendingPairAs(
            address(core),
            _protocolId,
            _collateral,
            uint256(Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID)
        );
        
        // Check that the new pair has the incremented ID
        uint256 newCollateralId = deployer.collateralId(_protocolId, _borrowToken, _collateralToken);
        assertEq(newCollateralId, currentCollateralId + 1, "Collateral ID should be incremented");
        
        // Verify the pair name reflects the new ID
        string memory expectedName = string(
            abi.encodePacked(
                "Resupply Pair (",
                deployer.platformNameById(_protocolId),
                ": ",
                IERC20Metadata(_borrowToken).symbol(),
                "/",
                IERC20Metadata(_collateralToken).symbol(),
                ") - ",
                newCollateralId.toString()
            )
        );
        assertEq(newPair.name(), expectedName, "Pair name should reflect correct ID");
        
        console2.log("New pair address:", address(newPair));
        console2.log("New pair name:", newPair.name());
        console2.log("New collateral ID:", newCollateralId);
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
        string memory expectedName = "Resupply Pair (CurveLend: crvUSD/sfrxUSD) - 2";
        assertEq(actualName, expectedName);
    }

    function test_updateProtocolData() public {
        vm.prank(address(core));
        uint256 protocolId = deployer.addSupportedProtocol("TestProtocol", 1e18, 1e17, bytes4(0), bytes4(0));
        vm.prank(address(core));
        deployer.updateSupportedProtocol(protocolId, "TestProtocol2", 1e18, 1e17, bytes4(0), bytes4(0));
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
            IResupplyPairDeployer.InvalidBorrowOrCollateralTokenLookup.selector
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

    function test_SharePriceManipulation() public {
        uint256 AIRDROP_AMOUNT = 10_000e18;
        IERC20 crvusd = IERC20(Mainnet.CRVUSD_ERC20);
        address curveLendCollat = 0x865377367054516e17014CcdED1e7d814EDC9ce4; // DOLA
        (address _vault, address gauge, uint256 convexPoolId) = deployCurveLendingVaultAndGauge(address(curveLendCollat));
        ICurveLendingVault vault = ICurveLendingVault(_vault);
        address controller = vault.controller();
        assertNotEq(_vault, address(0));

        deal(Mainnet.CRVUSD_ERC20, address(this), 1_000_000e18);
        crvusd.approve(_vault, type(uint256).max);
        vault.deposit(1e18, address(this));
        uint256 originalSharePrice = vault.convertToAssets(1e18);

        // Airdrop to the vault controller to inflate share value
        crvusd.transfer(vault.controller(), AIRDROP_AMOUNT);
        uint256 newSharePrice = vault.convertToAssets(1e18);
        assertGt(newSharePrice, originalSharePrice);

        // Reverts 
        vm.expectRevert();
        deployLendingPair(0, _vault, convexPoolId);
        
        // Clear the airdrop amount from controller to get pps back to normal
        vm.prank(vault.controller());
        crvusd.transfer(address(this), AIRDROP_AMOUNT);
        deployLendingPair(0, _vault, convexPoolId);
    }

    function _predictPairAddress(uint256 _protocolId, address _collateral, uint256 _stakingId) internal view returns(address){
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
            _protocolId == 0 ? Mainnet.CONVEX_BOOSTER : address(0),
            _stakingId
        );
        return _pairAddress;
    }

}