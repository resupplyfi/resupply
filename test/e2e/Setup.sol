// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Protocol, Mainnet, DeploymentConfig } from "src/Constants.sol";

// DAO Contracts
import { Test } from "lib/forge-std/src/Test.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IGovStaker } from "src/interfaces/IGovStaker.sol";
import { GovStaker } from "src/dao/staking/GovStaker.sol";
import { Core } from "src/dao/Core.sol";
import { Voter } from "src/dao/Voter.sol";
import { MockToken } from "test/mocks/MockToken.sol";
import { GovStakerEscrow } from "src/dao/staking/GovStakerEscrow.sol";
import { IGovStakerEscrow } from "src/interfaces/IGovStakerEscrow.sol";
import { EmissionsController } from "src/dao/emissions/EmissionsController.sol";
import { GovToken } from "src/dao/GovToken.sol";
import { IGovToken } from "src/interfaces/IGovToken.sol";
import { VestManager } from "src/dao/tge/VestManager.sol";
import { Treasury } from "src/dao/Treasury.sol";
import { PermaStaker } from "src/dao/tge/PermaStaker.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";

// Protocol Contracts
import { Stablecoin } from "src/protocol/Stablecoin.sol";
import { SavingsReUSD } from "src/protocol/sreusd/sreUSD.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { InsurancePool } from "src/protocol/InsurancePool.sol";
import { BasicVaultOracle } from "src/protocol/BasicVaultOracle.sol";
import { UnderlyingOracle } from "src/protocol/UnderlyingOracle.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";
import { Swapper } from "src/protocol/Swapper.sol";
import { PriceWatcher } from "src/protocol/PriceWatcher.sol";

// Incentive Contracts
import { SimpleRewardStreamer } from "src/protocol/SimpleRewardStreamer.sol";
import { FeeDeposit } from "src/protocol/FeeDeposit.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { SimpleReceiverFactory } from "src/dao/emissions/receivers/SimpleReceiverFactory.sol";

// Others
import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";
import { FeeLogger } from "src/protocol/FeeLogger.sol";
import { ReusdOracle } from "src/protocol/ReusdOracle.sol";
import { ICurveOneWayLendingFactory } from "src/interfaces/curve/ICurveOneWayLendingFactory.sol";
import { IConvexPoolManager } from "src/interfaces/convex/IConvexPoolManager.sol";
import { IConvexStaking } from "src/interfaces/convex/IConvexStaking.sol";
import { ICurveFactory } from "src/interfaces/curve/ICurveFactory.sol";
import { ICurveEscrow } from "src/interfaces/curve/ICurveEscrow.sol";
import { ICurveGaugeController } from "src/interfaces/curve/ICurveGaugeController.sol";


contract Setup is Test {
    address public immutable _THIS;
    // Deployer constants
    uint256 public constant epochLength = 1 weeks;
    uint256 internal constant GOV_TOKEN_INITIAL_SUPPLY = 60_000_000e18;
    address internal constant FRAX_VEST_TARGET = address(0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27);
    address internal constant PRISMA_TOKENS_BURN_ADDRESS = address(0xdead);

    Core public core;
    GovStaker public staker;
    Voter public voter;
    GovToken public govToken;
    GovToken public stakingToken;
    EmissionsController public emissionsController;
    VestManager public vestManager;
    ResupplyRegistry public registry;
    address public user1 = address(0x11);
    address public user2 = address(0x22);
    address public user3 = address(0x33);
    address public dev = address(0x42069);
    address public tempGov = address(987);
    Treasury public treasury;
    PermaStaker public permaStaker1;
    PermaStaker public permaStaker2;
    Stablecoin public stablecoin;
    SavingsReUSD public stakedStable;
    BasicVaultOracle public oracle;
    UnderlyingOracle public underlyingoracle;
    InterestRateCalculatorV2 public rateCalculator;
    ResupplyPairDeployer public deployer;
    RedemptionHandler public redemptionHandler;
    LiquidationHandler public liquidationHandler;
    RewardHandler public rewardHandler;
    FeeDeposit public feeDeposit;
    FeeDepositController public feeDepositController;
    SimpleRewardStreamer public ipStableStream;
    SimpleRewardStreamer public ipEmissionStream;
    SimpleRewardStreamer public pairEmissionStream;
    InsurancePool public insurancePool;
    SimpleReceiverFactory public receiverFactory;
    SimpleReceiver public debtReceiver;
    SimpleReceiver public insuranceEmissionsReceiver;
    PriceWatcher public priceWatcher;
    Swapper public defaultSwapper;
    IERC20 public frxusdToken;
    IERC20 public crvusdToken;
    ResupplyPair public testPair;
    ResupplyPair public testPair2;
    ICurveExchange public swapPoolsCrvUsd;
    ICurveExchange public swapPoolsFrxusd;
    FeeLogger public feeLogger;
    ReusdOracle public reusdOracle;
    
    constructor() {
        _THIS = address(this);
    }

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        deployDaoContracts();
        deployProtocolContracts();
        deployRewardsContracts();
        setInitialEmissionReceivers();
        deployCurvePools();
        deployDefaultLendingPairs();
        deal(address(govToken), user1, 1_000_000 * 10 ** 18);
        vm.prank(user1);
        govToken.approve(address(staker), type(uint256).max);

        frxusdToken = IERC20(Mainnet.FRXUSD_ERC20);
        crvusdToken = IERC20(Mainnet.CRVUSD_ERC20);

        // Setup registry
        vm.startPrank(address(core));
        registry.setRedemptionHandler(address(redemptionHandler));
        registry.setLiquidationHandler(address(liquidationHandler));
        registry.setInsurancePool(address(insurancePool));
        registry.setRewardHandler(address(rewardHandler));
        stablecoin.setOperator(address(registry), true);
        vm.stopPrank();

        // label all the used addresses for traces
        vm.label(address(tempGov), "Temp Gov");
        vm.label(address(core), "Core");
        vm.label(address(voter), "Voter");
        vm.label(address(govToken), "Gov Token");
        vm.label(address(emissionsController), "Emissions Controller");
        vm.label(address(permaStaker1), "PermaStaker 1");
        vm.label(address(permaStaker2), "PermaStaker 2");
        vm.label(address(staker), "Gov Staker");
        vm.label(address(treasury), "Treasury");
    }

    function deployProtocolContracts() public {
        oracle = new BasicVaultOracle("Basic Vault Oracle");
        underlyingoracle = new UnderlyingOracle("Underlying Token Oracle");
        address[] memory previouslyDeployedPairs;
        ResupplyPairDeployer.DeployInfo[] memory previouslyDeployedPairsInfo;
        deployer = new ResupplyPairDeployer(
            address(core),
            address(registry),
            address(govToken),
            address(core),
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
        );
        deal(Mainnet.CRVUSD_ERC20, address(deployer), 100e18);
        deal(Mainnet.FRXUSD_ERC20, address(deployer), 100e18);

        vm.startPrank(address(core));
        deployer.setCreationCode(type(ResupplyPair).creationCode);
        deployer.addSupportedProtocol(
            "CurveLend",
            1e18,
            1e17,
            bytes4(keccak256("asset()")),           // borrowLookupSig
            bytes4(keccak256("collateral_token()")) // collateralLookupSig
        );
        deployer.addSupportedProtocol(
            "Fraxlend",
            1e18,
            1e17,
            bytes4(keccak256("asset()")),           // borrowLookupSig
            bytes4(keccak256("collateralContract()")) // collateralLookupSig
        );
        vm.stopPrank();

        redemptionHandler = new RedemptionHandler(address(core),address(registry), address(underlyingoracle));
    }

    function deployRewardsContracts() public {
        address[] memory rewards = new address[](3);
        rewards[0] = address(govToken);
        rewards[1] = address(frxusdToken);
        rewards[2] = address(crvusdToken);


        address simpleReceiverImplementation = address(new 
            SimpleReceiver(
                address(core), 
                address(emissionsController)
            )
        );
        receiverFactory = new SimpleReceiverFactory(address(core), 
            address(emissionsController), 
            address(simpleReceiverImplementation)
        );

        vm.prank(address(core));
        debtReceiver = SimpleReceiver(receiverFactory.deployNewReceiver("Debt Receiver", new address[](0)));
        vm.prank(address(core));
        insuranceEmissionsReceiver = SimpleReceiver(receiverFactory.deployNewReceiver("Insurance Receiver", new address[](0)));
        
        insurancePool = new InsurancePool(
            address(core),
            address(registry),
            address(stablecoin),
            rewards,
            address(insuranceEmissionsReceiver)
        );
        liquidationHandler = new LiquidationHandler(
            address(core), 
            address(registry), 
            address(insurancePool)
        );

        //seed insurance pool
        vm.prank(address(core));
        stablecoin.transfer(address(insurancePool),1e18);

        ipStableStream = new SimpleRewardStreamer(
            address(core),
            address(registry),
            address(stablecoin), 
            address(insurancePool)
        );

        ipEmissionStream = new SimpleRewardStreamer(
            address(core),
            address(registry),
            address(stakingToken),
            address(insurancePool)
        );
        pairEmissionStream = new SimpleRewardStreamer(
            address(core),
            address(registry),
            address(stakingToken), 
            address(0)
        );
        feeDepositController = new FeeDepositController(
            address(core), 
            address(registry),
            200_000,
            1000, 
            500,
            1500
        );
        //attach fee deposit controller to fee deposit
        vm.prank(address(core));
        feeDeposit.setOperator(address(feeDepositController));

        rewardHandler = new RewardHandler(
            address(core),
            address(registry),
            address(insurancePool), 
            address(debtReceiver),
            address(pairEmissionStream),
            address(ipEmissionStream),
            address(ipStableStream)
        );

        vm.startPrank(address(core));
        //add stablecoin as a reward to gov staker
        staker.addReward(address(stablecoin), address(rewardHandler), uint256(7 days));
        debtReceiver.setApprovedClaimer(address(rewardHandler), true);
        insuranceEmissionsReceiver.setApprovedClaimer(address(rewardHandler), true);
        vm.stopPrank();
    }

    function setInitialEmissionReceivers() public{
        vm.startPrank(address(core));
        //add receivers
        emissionsController.registerReceiver(address(debtReceiver));
        emissionsController.registerReceiver(address(insuranceEmissionsReceiver));
        uint256 debtReceiverId = emissionsController.receiverToId(address(debtReceiver));
        uint256 insuranceReceiverId = emissionsController.receiverToId(address(insuranceEmissionsReceiver));
        //todo other receivers (voting, etc)

        //set weights
        uint256[] memory receivers = new uint256[](2);
        receivers[0] = debtReceiverId;
        receivers[1] = insuranceReceiverId;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 8000;
        weights[1] = 2000;
        emissionsController.setReceiverWeights(receivers,weights);
        vm.stopPrank();
    }

    function deployDaoContracts() public {
        address[3] memory redemptionTokens;
        redemptionTokens[0] = address(new MockToken('PRISMA', 'PRISMA'));
        redemptionTokens[1] = address(new MockToken('yPRISMA', 'yPRISMA'));
        redemptionTokens[2] = address(new MockToken('cvxPRISMA', 'cvxPRISMA'));

        address registryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this))+3);
        core = new Core(tempGov, epochLength);

        // The following logic re-assigns CORE to a target address for all e2e tests
        vm.etch(Protocol.CORE, address(core).code);
        core = Core(Protocol.CORE);
        vm.prank(address(core));
        core.setVoter(address(voter));

        address vestManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this))+4);
        govToken = new GovToken(
            address(core), 
            vestManagerAddress,
            GOV_TOKEN_INITIAL_SUPPLY,
            Mainnet.LAYERZERO_ENDPOINTV2,
            "Resupply", 
            "RSUP"
        );
        stablecoin = new Stablecoin(address(core), Mainnet.LAYERZERO_ENDPOINTV2);
        registry = new ResupplyRegistry(address(core), address(stablecoin), address(govToken));
        assertEq(address(registry), registryAddress);
        staker = new GovStaker(address(core), address(registry), address(govToken), 2);
        vestManager = new VestManager(
            address(core), 
            address(govToken),
            PRISMA_TOKENS_BURN_ADDRESS,   // Burn address
            redemptionTokens  // Redemption tokens
        );
        assertEq(address(vestManager), vestManagerAddress);
        
        voter = new Voter(address(core), IGovStaker(address(staker)), 100, 3000);
        vm.prank(address(core));
        registry.setAddress("VOTER", address(voter));
        stakingToken = govToken;

        vm.prank(address(core));
        core.setVoter(address(voter));
        
        emissionsController = new EmissionsController(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            3,      // epochs per
            2e16,   // tail rate
            0       // Bootstrap epochs
        );

        vm.prank(address(core));
        govToken.setMinter(address(emissionsController));

        // The following logic re-assigns TREASURY to a target address for all e2e tests
        treasury = new Treasury(address(core));
        vm.etch(Protocol.TREASURY, address(treasury).code);
        treasury = Treasury(payable(Protocol.TREASURY));

        vm.prank(address(core));
        registry.setStaker(address(staker));
        permaStaker1 = new PermaStaker(address(core), address(registry), user1, address(vestManager), "Yearn");
        permaStaker2 = new PermaStaker(address(core), address(registry), user2, address(vestManager), "Convex");
        assertEq(permaStaker1.owner(), user1);
        assertEq(permaStaker2.owner(), user2);

        uint256 maxdistro = 2e17 / uint256( 365 days );
        feeLogger = new FeeLogger(address(core), address(registry));
        reusdOracle = new ReusdOracle("Reusd Oracle");
        vm.prank(address(core));
        registry.setAddress("REUSD_ORACLE", address(reusdOracle));
        priceWatcher = new PriceWatcher(address(registry));
        rateCalculator = new InterestRateCalculatorV2(
            "V2", //suffix
            2e16 / uint256(365 days), //2%
            5e17, //rate ratio base
            1e17, //rate ratio additional
            address(priceWatcher) //price watcher
        );
        feeDeposit = new FeeDeposit(address(core), address(registry), address(stablecoin));
        vm.startPrank(address(core));
        registry.setTreasury(address(treasury));
        registry.setStaker(address(staker));
        registry.setAddress("FEE_LOGGER", address(feeLogger));
        registry.setAddress("PRICE_WATCHER", address(priceWatcher));
        registry.setFeeDeposit(address(feeDeposit));
        vm.stopPrank();

        stakedStable = new SavingsReUSD(address(core), address(registry), Mainnet.LAYERZERO_ENDPOINTV2, address(stablecoin), "Staked reUSD", "sreUSD", maxdistro);
        vm.prank(address(core));
        registry.setAddress("SREUSD", address(stakedStable));
    }

    function deployLendingPair(uint256 _protocolId, address _collateral, uint256 _stakingId) public returns(ResupplyPair p){
        return deployLendingPairWithCustomConfigAs(address(core), _protocolId, _collateral, _stakingId);
    }

    function deployLendingPairWithCustomConfigAs(address _deployer, uint256 _protocolId, address _collateral, uint256 _stakingId) public returns(ResupplyPair p){
        vm.startPrank(address(_deployer));
        address _pairAddress = deployer.deploy(
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
            _protocolId == 0 ? _stakingId : 0
        );
        if(_pairAddress == address(0)) {
            vm.stopPrank();
            return ResupplyPair(address(0));
        }
        registry.addPair(_pairAddress);
        p = ResupplyPair(_pairAddress);
        // ensure default state is written
        assertGt(p.minimumBorrowAmount(), 0);
        assertGt(p.minimumRedemption(), 0);
        assertGt(p.minimumLeftoverDebt(), 0);
        vm.stopPrank();
        return p;
    }

    function deployLendingPairWithDefaultConfigAs(address _deployer, uint256 _protocolId, address _collateral, uint256 _stakingId) public returns(ResupplyPair){
        vm.prank(address(_deployer));
        address _pairAddress = deployer.deployWithDefaultConfig(
            _protocolId,
            _collateral,
            _protocolId == 0 ? Mainnet.CONVEX_BOOSTER : address(0),
            _protocolId == 0 ? _stakingId : 0
        );
        return ResupplyPair(_pairAddress);
    }

    function deployDefaultLendingPairs() public{
        //curve lend
        testPair = deployLendingPair(0,Mainnet.CURVELEND_SDOLA_CRVUSD, Mainnet.CURVELEND_SDOLA_CRVUSD_ID);
        testPair2 = deployLendingPair(0,Mainnet.CURVELEND_SUSDE_CRVUSD, Mainnet.CURVELEND_SUSDE_CRVUSD_ID);
        deployLendingPair(0,Mainnet.CURVELEND_USDE_CRVUSD, Mainnet.CURVELEND_USDE_CRVUSD_ID);
        deployLendingPair(0,Mainnet.CURVELEND_TBTC_CRVUSD_DEPRECATED, Mainnet.CURVELEND_TBTC_CRVUSD_ID);
        deployLendingPair(0,Mainnet.CURVELEND_WBTC_CRVUSD, Mainnet.CURVELEND_WBTC_CRVUSD_ID);
        deployLendingPair(0,Mainnet.CURVELEND_WETH_CRVUSD, Mainnet.CURVELEND_WETH_CRVUSD_ID);
        deployLendingPair(0,Mainnet.CURVELEND_WSTETH_CRVUSD, Mainnet.CURVELEND_WSTETH_CRVUSD_ID);
        deployLendingPair(0,Mainnet.CURVELEND_SFRXUSD_CRVUSD, Mainnet.CURVELEND_SFRXUSD_CRVUSD_ID);
        
        //fraxlend
        deployLendingPair(1,Mainnet.FRAXLEND_SFRXETH_FRXUSD, 0);
        deployLendingPair(1,Mainnet.FRAXLEND_SUSDE_FRXUSD, 0);
        deployLendingPair(1,Mainnet.FRAXLEND_WBTC_FRXUSD, 0);
        deployLendingPair(1,Mainnet.FRAXLEND_SCRVUSD_FRXUSD, 0);
    }

    function deployCurvePools() public{
        address[] memory coins = new address[](2);
        coins[0] = address(stablecoin);
        coins[1] = Mainnet.SCRVUSD_ERC20;
        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[1] = 3; //second coin is erc4626
        bytes4[] memory methods = new bytes4[](2);
        address[] memory oracles = new address[](2);
        address crvusdAmm = ICurveExchange(Mainnet.CURVE_STABLE_FACTORY).deploy_plain_pool(
            "reUSD/scrvUSD", //name
            "reusdscrv", //symbol
            coins, //coins
            200, //A
            4000000, //fee
            50000000000, //off peg multi
            866, //ma exp time
            0, //implementation index
            assetTypes, //asset types - normal + erc4626
            methods, //method ids
            oracles //oracles
        );
        swapPoolsCrvUsd = ICurveExchange(crvusdAmm);

        coins[1] = Mainnet.SFRXUSD_ERC20;
        address fraxAmm = ICurveExchange(Mainnet.CURVE_STABLE_FACTORY).deploy_plain_pool(
            "reUSD/sfrxUSD", //name
            "reusdsfrx", //symbol
            coins, //coins
            200, //A
            4000000, //fee
            50000000000, //off peg multi
            866, //ma exp time
            0, //implementation index
            assetTypes, //asset types - normal + erc4626
            methods, //method ids
            oracles //oracles
        );
        swapPoolsFrxusd = ICurveExchange(fraxAmm);


        //deploy swapper
        defaultSwapper = new Swapper(address(core), address(registry));

        //set routes
        vm.startPrank(address(core));

        Swapper.SwapInfo memory swapinfo;

        //reusd to scrvusd
        swapinfo.swappool = crvusdAmm;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 1;
        swapinfo.swaptype = 1;
        defaultSwapper.addPairing(
            address(stablecoin),
            Mainnet.SCRVUSD_ERC20,
            swapinfo
        );

        //scrvusd to reusd
        swapinfo.swappool = crvusdAmm;
        swapinfo.tokenInIndex = 1;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 1;
        defaultSwapper.addPairing(
            Mainnet.SCRVUSD_ERC20,
            address(stablecoin),
            swapinfo
        );

        //scrvusd withdraw to crvusd
        swapinfo.swappool = Mainnet.SCRVUSD_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 3;
        defaultSwapper.addPairing(
            Mainnet.SCRVUSD_ERC20,
            Mainnet.CRVUSD_ERC20,
            swapinfo
        );

        //crvusd deposit to scrvusd
        swapinfo.swappool = Mainnet.SCRVUSD_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 2;
        defaultSwapper.addPairing(
            Mainnet.CRVUSD_ERC20,
            Mainnet.SCRVUSD_ERC20,
            swapinfo
        );

        //reusd to sfrxusd
        swapinfo.swappool = fraxAmm;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 1;
        swapinfo.swaptype = 1;
        defaultSwapper.addPairing(
            address(stablecoin),
            Mainnet.SFRXUSD_ERC20,
            swapinfo
        );

        //sfrxusd to reusd
        swapinfo.swappool = fraxAmm;
        swapinfo.tokenInIndex = 1;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 1;
        defaultSwapper.addPairing(
            Mainnet.SFRXUSD_ERC20,
            address(stablecoin),
            swapinfo
        );

        //sfrxusd withdraw to frxusd
        swapinfo.swappool = Mainnet.SFRXUSD_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 3;
        defaultSwapper.addPairing(
            Mainnet.SFRXUSD_ERC20,
            Mainnet.FRXUSD_ERC20,
            swapinfo
        );

        //frxusd deposit to sfrxusd
        swapinfo.swappool = Mainnet.SFRXUSD_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 2;
        defaultSwapper.addPairing(
            Mainnet.FRXUSD_ERC20,
            Mainnet.SFRXUSD_ERC20,
            swapinfo
        );


        //set swapper to registry
        address[] memory swappers = new address[](1);
        swappers[0] = address(defaultSwapper);
        registry.setDefaultSwappers(swappers);
        vm.stopPrank();
    }

    function printAddresses() public view {
        console.log("======================================");
        console.log("    Protocol Contracts     ");
        console.log("======================================");
        console.log("Registry: ", address(registry));
        console.log("Deployer: ", address(deployer));
        console.log("govToken: ", address(stakingToken));
        console.log("stablecoin: ", address(stablecoin));
        console.log("insurancePool: ", address(insurancePool));
        console.log("ipStableStream: ", address(ipStableStream));
        console.log("pairEmissionStream: ", address(pairEmissionStream));
        console.log("feeDeposit: ", address(feeDeposit));
        console.log("feeDepositController: ", address(feeDepositController));
        console.log("redemptionHandler: ", address(redemptionHandler));
        console.log("liquidationHandler: ", address(liquidationHandler));
        console.log("rewardHandler: ", address(rewardHandler));
        console.log("debtReceiver: ", address(debtReceiver));
        console.log("swap scrvusd: ", address(swapPoolsCrvUsd));
        console.log("swap sfrxusd: ", address(swapPoolsFrxusd));
    }

    function getEmissionsSchedule() public view returns (uint256[] memory) {
        uint256[] memory schedule = new uint256[](5);
        // tail rate 2%
        schedule[0] = DeploymentConfig.EMISSIONS_SCHEDULE_YEAR_5;
        schedule[1] = DeploymentConfig.EMISSIONS_SCHEDULE_YEAR_4;
        schedule[2] = DeploymentConfig.EMISSIONS_SCHEDULE_YEAR_3;
        schedule[3] = DeploymentConfig.EMISSIONS_SCHEDULE_YEAR_2;
        schedule[4] = DeploymentConfig.EMISSIONS_SCHEDULE_YEAR_1;
        return schedule;
    }

    function deployCurveLendingVaultAndGauge(
        address _collateral
    ) public returns(address vault, address gauge, uint256 convexPoolId){
        // default values taken from https://etherscan.io/tx/0xe1d3e1c4fef7753e5fff72dfb96861e0fec455d17ebfce04a2858b9169c462b7
        vault = ICurveOneWayLendingFactory(Mainnet.CURVE_ONE_WAY_LENDING_FACTORY).create(
            Mainnet.CRVUSD_ERC20, //borrowed token
            _collateral,        //collateral token
            285,                //A
            2000000000000000,   //fee
            13000000000000000,  //loan discount
            10000000000000000,  //liquidation discount
            0x88822eE517Bfe9A1b97bf200b0b6D3F356488fF2, //price oracle
            "sDOLA-Long2",      //name
            31709791,           //min borrow rate
            31709791            //max borrow rate
        );
        (gauge, convexPoolId) = _deployAndConfigureGauge(vault);
    }

    function _deployAndConfigureGauge(address _vault) public returns(address gauge, uint256 convexPoolId){
        gauge = ICurveFactory(Mainnet.CURVE_ONE_WAY_LENDING_FACTORY).deploy_gauge(_vault);
        ICurveGaugeController gaugeController = ICurveGaugeController(Mainnet.CURVE_GAUGE_CONTROLLER);
        // We need to put some weight on this gauge via gauge controller, so we lock some CRV
        deal(Mainnet.CRV_ERC20, address(this), 1_000_000e18);
        IERC20(Mainnet.CRV_ERC20).approve(Mainnet.CURVE_ESCROW, type(uint256).max);
        ICurveEscrow(Mainnet.CURVE_ESCROW).create_lock(1_000_000e18, vm.getBlockTimestamp() + 200 weeks);
        vm.prank(gaugeController.admin());
        gaugeController.add_gauge(gauge, 1);
        gaugeController.vote_for_gauge_weights(gauge, 10_000);

        // Add the gauge to convex
        IConvexPoolManager(Mainnet.CONVEX_POOL_MANAGER).addPool(gauge);
        // (address lptoken, address token, address convexGauge, address crvRewards, address stash, bool shutdown) = IConvexStaking(Mainnet.CONVEX_BOOSTER).poolInfo(gauge);
        convexPoolId = IConvexStaking(Mainnet.CONVEX_BOOSTER).poolLength() - 1;
    }

    function setOperatorPermission(address operator, address target, bytes4 selector, bool authorized) public {
        vm.prank(address(core));
        core.setOperatorPermissions(
            operator,
            target,
            selector,
            authorized,
            IAuthHook(address(0))
        );
    }

    function stakeGovToken(uint256 amount) public {
        deal(address(govToken), address(this), amount);
        govToken.approve(address(staker), amount);
        staker.stake(address(this), amount);
    }
}