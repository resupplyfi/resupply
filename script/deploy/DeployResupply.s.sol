import "src/Constants.sol" as Constants;
import { DeploymentConfig } from "script/deploy/dependencies/DeploymentConfig.sol";
import { console } from "forge-std/console.sol";
import { console2 } from "forge-std/console2.sol";
import { DeployResupplyDao } from "./dependencies/DeployResupplyDao.s.sol";
import { DeployResupplyProtocol } from "./dependencies/DeployResupplyProtocol.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGovStaker } from "src/interfaces/IGovStaker.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { Stablecoin } from "src/protocol/Stablecoin.sol";
import { EmissionsController } from "src/dao/emissions/EmissionsController.sol";
import { GovToken } from "src/dao/GovToken.sol";
import { Swapper } from "src/protocol/Swapper.sol";
import { ICurveExchange } from "src/interfaces/ICurveExchange.sol";

contract DeployResupply is DeployResupplyDao, DeployResupplyProtocol {
    address public crvusdPool;
    address public fraxPool;

    function run() public virtual {
        deployMode = DeployMode.FORK;
        deployAll();
    }

    function deployAll() isBatch(deployer) public {
        if (deployMode == DeployMode.FORK) defaultBorrowLimit = 50_000_000 * 1e18; // default for testnets
        setEthBalance(deployer, 10e18);
        deployDaoContracts();
        deployProtocolContracts();
        configurationStep1();
        deployRewardsContracts();
        configureProtocolContracts();
        (permaStaker1, permaStaker2) = deployPermaStakers();
        setupEmissionsReceivers();
        grantOperatorPermissions();
        if (block.chainid == Constants.Mainnet.CHAIN_ID) {
            deployCurvePools();
            deploySwapper();
            deployDefaultLendingPairs();
        }
        printBatchGasUsage();
    }

    function printBatchGasUsage() public {
        uint256 totalBatches = getTotalBatches();
        console2.log(unicode"-------- ⛽ Gas Analysis ⛽ ------------");
        console2.log("Total batches:", totalBatches);
        uint256 totalGas = 0;
        for (uint256 i = 0; i < totalBatches; i++) {
            (uint256 txCount, uint256 batchGas) = getBatchInfo(i);
            console2.log("  -batch %d , %d txns: %d gas", i+1, txCount, batchGas);
            totalGas += batchGas;
            executeBatch(deployMode == DeployMode.PRODUCTION);
        }
        console2.log("-Total gas used:", totalGas);
    }

    // Deploy incentives reUSD/RSUP incentives receivers and register all receivers with the emissions controller
    function setupEmissionsReceivers() public {
        address[] memory approvedClaimers = new address[](1);
        approvedClaimers[0] = deployer;
        // Deploy the reUSD Incentives Receiver
        bytes memory result = _executeCore(
            address(receiverFactory), 
            abi.encodeWithSelector(receiverFactory.deployNewReceiver.selector, "reUSD Incentives Receiver", approvedClaimers)
        );
        result = abi.decode(result, (bytes)); // our result was double encoded, so we decode it once
        address reusdLPIncentivesReceiver = abi.decode(result, (address)); // decode the bytes result to an address
        console.log("reUSD LP Incentives Receiver deployed at", address(reusdLPIncentivesReceiver));

        // Register the receivers with the emissions controller
        _executeCore(address(emissionsController), abi.encodeWithSelector(EmissionsController.registerReceiver.selector, address(debtReceiver)));
        _executeCore(address(emissionsController), abi.encodeWithSelector(EmissionsController.registerReceiver.selector, address(insuranceEmissionsReceiver)));
        _executeCore(address(emissionsController), abi.encodeWithSelector(EmissionsController.registerReceiver.selector, address(reusdLPIncentivesReceiver)));
        console.log("Receivers registered with the emissions controller");

        // Set the weights for the receivers
        uint256[] memory receiverIds = new uint256[](3);
        receiverIds[0] = 0;
        receiverIds[1] = 1;
        receiverIds[2] = 2;
        uint256[] memory weights = new uint256[](3);
        weights[0] = DeploymentConfig.INITIAL_EMISSIONS_WEIGHT_DEBT;
        weights[1] = DeploymentConfig.INITIAL_EMISSIONS_WEIGHT_INSURANCE_POOL;
        weights[2] = DeploymentConfig.INITIAL_EMISSIONS_WEIGHT_LP;
        _executeCore(address(emissionsController), abi.encodeWithSelector(EmissionsController.setReceiverWeights.selector, receiverIds, weights));
        console.log("Receiver weights set");
    }

    function deployDefaultLendingPairs() public {
        _executeCore(
            address(pairDeployer), 
            abi.encodeWithSelector(
                ResupplyPairDeployer.addSupportedProtocol.selector, 
                "CurveLend", 
                bytes4(keccak256("asset()")), 
                bytes4(keccak256("collateral_token()"))
            )
        );
        _executeCore(
            address(pairDeployer), 
            abi.encodeWithSelector(
                ResupplyPairDeployer.addSupportedProtocol.selector, 
                "Fraxlend", 
                bytes4(keccak256("asset()")), 
                bytes4(keccak256("collateralContract()"))
            )
        );

        //curve pairs
        address pair = deployLendingPair(0, Constants.Mainnet.CURVELEND_SFRXUSD_CRVUSD, Constants.Mainnet.CONVEX_BOOSTER, Constants.Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID);
        console.log('pair deployed: curvelend_sfrxusd_crvusd', pair);
        writeAddressToJson("PAIR_CURVELEND_SFRXUSD_CRVUSD", pair);
        pair = deployLendingPair(0, Constants.Mainnet.CURVELEND_SDOLA_CRVUSD, Constants.Mainnet.CONVEX_BOOSTER, Constants.Mainnet.CURVELEND_SDOLA_CRVUSD_ID);
        console.log('pair deployed: curvelend_sdola_crvusd', pair);
        writeAddressToJson("PAIR_CURVELEND_SDOLA_CRVUSD", pair);
        pair = deployLendingPair(0, Constants.Mainnet.CURVELEND_SUSDE_CRVUSD, Constants.Mainnet.CONVEX_BOOSTER, Constants.Mainnet.CURVELEND_SUSDE_CRVUSD_ID);
        console.log('pair deployed: curvelend_susde_crvusd', pair);
        writeAddressToJson("PAIR_CURVELEND_SUSDE_CRVUSD", pair);
        pair = deployLendingPair(0, Constants.Mainnet.CURVELEND_USDE_CRVUSD, Constants.Mainnet.CONVEX_BOOSTER, Constants.Mainnet.CURVELEND_USDE_CRVUSD_ID);
        console.log('pair deployed: curvelend_usde_crvusd', pair);
        writeAddressToJson("PAIR_CURVELEND_USDE_CRVUSD", pair);
        pair = deployLendingPair(0, Constants.Mainnet.CURVELEND_TBTC_CRVUSD_DEPRECATED, Constants.Mainnet.CONVEX_BOOSTER, Constants.Mainnet.CURVELEND_TBTC_CRVUSD_ID);
        console.log('pair deployed: curvelend_tbtc_crvusd', pair);
        writeAddressToJson("PAIR_CURVELEND_TBTC_CRVUSD", pair);
        pair = deployLendingPair(0, Constants.Mainnet.CURVELEND_WBTC_CRVUSD, Constants.Mainnet.CONVEX_BOOSTER, Constants.Mainnet.CURVELEND_WBTC_CRVUSD_ID);
        console.log('pair deployed: curvelend_wbtc_crvusd', pair);
        writeAddressToJson("PAIR_CURVELEND_WBTC_CRVUSD", pair);
        pair = deployLendingPair(0, Constants.Mainnet.CURVELEND_WETH_CRVUSD, Constants.Mainnet.CONVEX_BOOSTER, Constants.Mainnet.CURVELEND_WETH_CRVUSD_ID);
        console.log('pair deployed: curvelend_weth_crvusd', pair);
        writeAddressToJson("PAIR_CURVELEND_WETH_CRVUSD", pair);
        pair = deployLendingPair(0, Constants.Mainnet.CURVELEND_WSTETH_CRVUSD, Constants.Mainnet.CONVEX_BOOSTER, Constants.Mainnet.CURVELEND_WSTETH_CRVUSD_ID);
        console.log('pair deployed: curvelend_wsteth_crvusd', pair);
        writeAddressToJson("PAIR_CURVELEND_WSTETH_CRVUSD", pair);


        //fraxlend pairs
        pair = deployLendingPair(1, Constants.Mainnet.FRAXLEND_SFRXETH_FRXUSD, address(0), 0);
        console.log('pair deployed: fraxlend_sfrxeth_frxusd', pair);
        writeAddressToJson("PAIR_FRAXLEND_SFRXETH_FRXUSD", pair);
        
        deployLendingPair(1,address(Constants.Mainnet.FRAXLEND_SUSDE_FRXUSD), address(0), uint256(0));
        console.log('pair deployed: fraxlend_susde_frxusd', pair);
        writeAddressToJson("PAIR_FRAXLEND_SUSDE_FRXUSD", pair);
        deployLendingPair(1,address(Constants.Mainnet.FRAXLEND_WBTC_FRXUSD), address(0), uint256(0));
        console.log('pair deployed: fraxlend_wbtc_frxusd', pair);
        writeAddressToJson("PAIR_FRAXLEND_WBTC_FRXUSD", pair);
        deployLendingPair(1,address(Constants.Mainnet.FRAXLEND_SCRVUSD_FRXUSD), address(0), uint256(0));
        console.log('pair deployed: fraxlend_scrvusd_frxusd', pair);
        writeAddressToJson("PAIR_FRAXLEND_SCRVUSD_FRXUSD", pair);
    }

    function configurationStep1() public {
        _executeCore(address(pairDeployer), abi.encodeWithSelector(ResupplyPairDeployer.setCreationCode.selector, type(ResupplyPair).creationCode));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setVestManager.selector, address(vestManager)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setTreasury.selector, address(treasury)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setStaker.selector, address(staker)));
    }

    function configureProtocolContracts() public {
        _executeCore(address(govToken), abi.encodeWithSelector(GovToken.setMinter.selector, address(emissionsController), true));
        _executeCore(address(feeDeposit), abi.encodeWithSelector(feeDeposit.setOperator.selector, address(feeDepositController)));
        _executeCore(address(staker), abi.encodeWithSelector(IGovStaker.addReward.selector, address(stablecoin), address(rewardHandler), uint256(7 days)));
        _executeCore(address(debtReceiver), abi.encodeWithSelector(SimpleReceiver.setApprovedClaimer.selector, address(rewardHandler), true));
        _executeCore(address(insuranceEmissionsReceiver), abi.encodeWithSelector(SimpleReceiver.setApprovedClaimer.selector, address(rewardHandler), true));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setRedemptionHandler.selector, address(redemptionHandler)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setLiquidationHandler.selector, address(liquidationHandler)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setInsurancePool.selector, address(insurancePool)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setFeeDeposit.selector, address(feeDeposit)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setRewardHandler.selector, address(rewardHandler)));
        _executeCore(address(stablecoin), abi.encodeWithSelector(Stablecoin.setOperator.selector, address(registry), true));
    }

    function grantOperatorPermissions() public {
        // During protocol launch phase, we grant the guardian multisig permissions to set the voter
        _executeCore(
            core, 
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector, 
                deployer, 
                address(core),
                ICore.setVoter.selector,
                true,
                address(0)
            )
        );
        console.log("Granted permissions to set voter");
        // Allow the guardian multisig to update proposal descriptions
        _executeCore(
            core, 
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector, 
                deployer, 
                address(voter),
                IVoter.updateProposalDescription.selector,
                true,
                address(0)
            )
        );
        console.log("Granted permissions to update proposal descriptions");
    }

    function deployCurvePools() public{
        address[] memory coins = new address[](2);
        coins[0] = address(stablecoin);
        coins[1] = DeploymentConfig.SCRVUSD;
        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[1] = 3; //second coin is erc4626
        bytes4[] memory methods = new bytes4[](2);
        address[] memory oracles = new address[](2);
        bytes memory result;
        result = addToBatch(
            address(Constants.Mainnet.CURVE_STABLE_FACTORY),
            abi.encodeWithSelector(ICurveExchange.deploy_plain_pool.selector,
                "reUSD/scrvUSD",    // name
                "reusdscrv",        // symbol
                coins,              // coins
                200,                // A
                2000000,            // fee
                50000000000,        // off peg multi
                866,                // ma exp time
                0,                  // implementation index
                assetTypes,         // asset types - normal + erc4626
                methods,            // method ids
                oracles             // oracles
            )
        );
        crvusdPool = abi.decode(result, (address));
        console.log("reUSD/scrvUSD Pool deployed at", crvusdPool);
        writeAddressToJson("REUSD_SCRVUSD_POOL", crvusdPool);
        //TODO, update to sfrxusd from sfrax
        coins[1] = DeploymentConfig.SFRXUSD;
        result = addToBatch(
            address(Constants.Mainnet.CURVE_STABLE_FACTORY),
            abi.encodeWithSelector(ICurveExchange.deploy_plain_pool.selector,
                "reUSD/sfrxUSD",    //name
                "reusdsfrx",        //symbol
                coins,              //coins
                200,                //A
                2000000,            //fee
                50000000000,        //off peg multi
                866,                //ma exp time
                0,                  //implementation index
                assetTypes,         //asset types - normal + erc4626
                methods,            //method ids
                oracles             //oracles
            )
        );
        fraxPool = abi.decode(result, (address));
        console.log("reUSD/sfrxUSD Pool deployed at", fraxPool);
        writeAddressToJson("REUSD_SFRXUSD_POOL", fraxPool);

        // deploy gauges
        result = addToBatch(
            address(Constants.Mainnet.CURVE_STABLE_FACTORY),
            abi.encodeWithSelector(ICurveExchange.deploy_gauge.selector,
                crvusdPool
            )
        );
        address crvusdGauge = abi.decode(result, (address));
        console.log("reUSD/scrvUSD Gauge deployed at", crvusdGauge);
        writeAddressToJson("REUSD_SCRVUSD_GAUGE", crvusdGauge);

        result = addToBatch(
            address(Constants.Mainnet.CURVE_STABLE_FACTORY),
            abi.encodeWithSelector(ICurveExchange.deploy_gauge.selector,
                fraxPool
            )
        );
        address fraxGauge = abi.decode(result, (address));
        console.log("reUSD/sfrxUSD Gauge deployed at", fraxGauge);
        writeAddressToJson("REUSD_SFRXUSD_GAUGE", fraxGauge);
    }

    function deploySwapper() public {
        //deploy swapper
        bytes32 salt = buildGuardedSalt(deployer, true, false, uint88(uint256(keccak256(bytes("Swapper")))));
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("Swapper.sol:Swapper"),
            abi.encode(
                address(core), 
                address(registry)
            )
        );
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (addressHasCode(predictedAddress)) revert("Swapper already deployed");
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(
                salt, 
                bytecode
            )
        );
        defaultSwapper = Swapper(predictedAddress);
        console.log("Swapper deployed at", address(defaultSwapper));
        writeAddressToJson("SWAPPER", predictedAddress);

        Swapper.SwapInfo memory swapinfo;

        //reusd to scrvusd
        swapinfo.swappool = crvusdPool;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 1;
        swapinfo.swaptype = 1;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, address(stablecoin), Constants.Mainnet.CURVE_SCRVUSD, swapinfo));

        //scrvusd to reusd
        swapinfo.swappool = crvusdPool;
        swapinfo.tokenInIndex = 1;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 1;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.CURVE_SCRVUSD, address(stablecoin), swapinfo));

        //scrvusd withdraw to crvusd
        swapinfo.swappool = Constants.Mainnet.CURVE_SCRVUSD;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 3;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.CURVE_SCRVUSD, Constants.Mainnet.CURVE_USD_ERC20, swapinfo));

        //crvusd deposit to scrvusd
        swapinfo.swappool = Constants.Mainnet.CURVE_SCRVUSD;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 2;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.CURVE_USD_ERC20, Constants.Mainnet.CURVE_SCRVUSD, swapinfo));

        //reusd to sfrxusd
        swapinfo.swappool = fraxPool;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 1;
        swapinfo.swaptype = 1;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, address(stablecoin), Constants.Mainnet.SFRXUSD_ERC20, swapinfo));

        //sfrxusd to reusd
        swapinfo.swappool = fraxPool;
        swapinfo.tokenInIndex = 1;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 1;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.SFRXUSD_ERC20, address(stablecoin), swapinfo));

        //sfrxusd withdraw to frxusd
        swapinfo.swappool = Constants.Mainnet.SFRXUSD_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 3;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.SFRXUSD_ERC20, Constants.Mainnet.FRXUSD_ERC20, swapinfo));

        //frxusd deposit to sfrxusd
        swapinfo.swappool = Constants.Mainnet.SFRXUSD_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 2;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.FRXUSD_ERC20, Constants.Mainnet.SFRXUSD_ERC20, swapinfo));


        //set swapper to registry
        address[] memory swappers = new address[](1);
        swappers[0] = address(defaultSwapper);
        _executeCore(address(registry), abi.encodeWithSelector(registry.setDefaultSwappers.selector, swappers));
        console.log("Swapper configured");
    }
}
