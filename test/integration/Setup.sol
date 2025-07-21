// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;
import { Protocol, Mainnet } from "src/Constants.sol";
import { DeploymentConfig } from "src/Constants.sol";

// DAO Contracts
import { Test } from "lib/forge-std/src/Test.sol";
import { console } from "lib/forge-std/src/console.sol";
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IGovStaker } from "src/interfaces/IGovStaker.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IGovStakerEscrow } from "src/interfaces/IGovStakerEscrow.sol";
import { IEmissionsController } from "src/interfaces/IEmissionsController.sol";
import { IGovToken } from "src/interfaces/IGovToken.sol";
import { IStablecoin } from "src/interfaces/IStablecoin.sol";
import { IBasicVaultOracle } from "src/interfaces/IBasicVaultOracle.sol";
import { IUnderlyingOracle } from "src/interfaces/IUnderlyingOracle.sol";
import { IInterestRateCalculator } from "src/interfaces/IInterestRateCalculator.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IPermastaker } from "src/interfaces/IPermastaker.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { ILiquidationHandler } from "src/interfaces/ILiquidationHandler.sol";
import { IRewardHandler } from "src/interfaces/IRewardHandler.sol";
import { IFeeDeposit } from "src/interfaces/IFeeDeposit.sol";
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { IVestManager } from "src/interfaces/IVestManager.sol";

// Protocol Contracts
import { IStablecoin } from "src/interfaces/IStablecoin.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IInsurancePool } from "src/interfaces/IInsurancePool.sol";
import { IBasicVaultOracle } from "src/interfaces/IBasicVaultOracle.sol";
import { IUnderlyingOracle } from "src/interfaces/IUnderlyingOracle.sol";
import { IInterestRateCalculator } from "src/interfaces/IInterestRateCalculator.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { ILiquidationHandler } from "src/interfaces/ILiquidationHandler.sol";
import { IRewardHandler } from "src/interfaces/IRewardHandler.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";

// Incentive Contracts
import { ISimpleRewardStreamer } from "src/interfaces/ISimpleRewardStreamer.sol";
import { IFeeDeposit } from "src/interfaces/IFeeDeposit.sol";
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { ISimpleReceiver } from "src/interfaces/ISimpleReceiver.sol";
import { ISimpleReceiverFactory } from "src/interfaces/ISimpleReceiverFactory.sol";

// Others
import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICurveOneWayLendingFactory } from "src/interfaces/curve/ICurveOneWayLendingFactory.sol";
import { ICurveFactory } from "src/interfaces/curve/ICurveFactory.sol";
import { ICurveGaugeController } from "src/interfaces/curve/ICurveGaugeController.sol";
import { ICurveEscrow } from "src/interfaces/curve/ICurveEscrow.sol";
import { IConvexPoolManager } from "src/interfaces/convex/IConvexPoolManager.sol";
import { IConvexStaking } from "src/interfaces/convex/IConvexStaking.sol";
import { IRetentionReceiver } from "src/interfaces/IRetentionReceiver.sol";
import { IRetentionIncentives } from "src/interfaces/IRetentionIncentives.sol";


contract Setup is Test {
    using SafeERC20 for IERC20;
    address public user = address(0x1);
    ICore public core = ICore(Protocol.CORE);
    IGovStaker public staker = IGovStaker(Protocol.GOV_STAKER);
    IVoter public voter = IVoter(Protocol.VOTER);
    IGovToken public govToken = IGovToken(Protocol.GOV_TOKEN);
    IEmissionsController public emissionsController = IEmissionsController(Protocol.EMISSIONS_CONTROLLER);
    IVestManager public vestManager = IVestManager(Protocol.VEST_MANAGER);
    IResupplyRegistry public registry = IResupplyRegistry(Protocol.REGISTRY);
    ITreasury public treasury = ITreasury(payable(Protocol.TREASURY));
    IPermastaker public permaStaker1 = IPermastaker(Protocol.PERMA_STAKER_CONVEX);
    IPermastaker public permaStaker2 = IPermastaker(Protocol.PERMA_STAKER_YEARN);
    IStablecoin public stablecoin = IStablecoin(Protocol.STABLECOIN);
    IBasicVaultOracle public oracle = IBasicVaultOracle(Protocol.BASIC_VAULT_ORACLE);
    IUnderlyingOracle public underlyingoracle = IUnderlyingOracle(Protocol.UNDERLYING_ORACLE);
    IInterestRateCalculator public rateCalculator = IInterestRateCalculator(Protocol.INTEREST_RATE_CALCULATOR);
    IResupplyPairDeployer public deployer = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER_V2);
    IRedemptionHandler public redemptionHandler = IRedemptionHandler(Protocol.REDEMPTION_HANDLER);
    ILiquidationHandler public liquidationHandler = ILiquidationHandler(Protocol.LIQUIDATION_HANDLER);
    IRewardHandler public rewardHandler = IRewardHandler(Protocol.REWARD_HANDLER);
    IFeeDeposit public feeDeposit = IFeeDeposit(Protocol.FEE_DEPOSIT);
    IFeeDepositController public feeDepositController = IFeeDepositController(Protocol.FEE_DEPOSIT_CONTROLLER);
    ISimpleRewardStreamer public ipStableStream = ISimpleRewardStreamer(Protocol.IP_STABLE_STREAM);
    ISimpleRewardStreamer public ipEmissionStream = ISimpleRewardStreamer(Protocol.EMISSION_STREAM_INSURANCE_POOL);
    ISimpleRewardStreamer public pairEmissionStream = ISimpleRewardStreamer(Protocol.EMISSIONS_STREAM_PAIR);
    IInsurancePool public insurancePool = IInsurancePool(Protocol.INSURANCE_POOL);
    ISimpleReceiverFactory public receiverFactory = ISimpleReceiverFactory(Protocol.SIMPLE_RECEIVER_FACTORY);
    ISimpleReceiver public debtReceiver = ISimpleReceiver(Protocol.DEBT_RECEIVER);
    ISimpleReceiver public insuranceEmissionsReceiver = ISimpleReceiver(Protocol.INSURANCE_POOL_RECEIVER);
    ISimpleReceiver public liquidityEmissionsReceiver = ISimpleReceiver(Protocol.LIQUIDITY_INCENTIVES_RECEIVER);
    ISwapper public defaultSwapper = ISwapper(Protocol.SWAPPER);
    IERC20 public frxusdToken = IERC20(Mainnet.FRXUSD_ERC20);
    IERC20 public crvusdToken = IERC20(Mainnet.CRVUSD_ERC20);
    IResupplyPair public testPair = IResupplyPair(Mainnet.FRAXLEND_SCRVUSD_FRXUSD);
    IResupplyPair public testPair2 = IResupplyPair(Mainnet.CURVELEND_SDOLA_CRVUSD);
    ICurveExchange public swapPoolsCrvUsd = ICurveExchange(Protocol.REUSD_SCRVUSD_POOL);
    ICurveExchange public swapPoolsFrxusd = ICurveExchange(Protocol.REUSD_SFRXUSD_POOL);
    IERC20 public frxusd = IERC20(Mainnet.FRXUSD_ERC20);
    IERC20 public crvusd = IERC20(Mainnet.CRVUSD_ERC20);
    IERC20 public sfrxusd = IERC20(Mainnet.SFRXUSD_ERC20);
    IERC20 public scrvusd = IERC20(Mainnet.SCRVUSD_ERC20);
    address public lzEndpoint = address(Mainnet.LAYERZERO_ENDPOINTV2);
    IRetentionReceiver public retentionReceiver = IRetentionReceiver(Protocol.RETENTION_RECEIVER);
    IRetentionIncentives public retention = IRetentionIncentives(Protocol.RETENTION_INCENTIVES);


    constructor() {}

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        deployer = IResupplyPairDeployer(registry.getAddress("PAIR_DEPLOYER"));
        clearPairImplementation();
    }

    function buyReUSD(uint256 _amountIn) public returns(uint256 _newprice){
        deal(address(scrvusd), address(this), _amountIn);
        IERC20(address(scrvusd)).forceApprove(address(swapPoolsCrvUsd), type(uint256).max);
        ICurveExchange(address(swapPoolsCrvUsd)).exchange(0,1, _amountIn, 0, address(this));
        _newprice = ICurveExchange(address(swapPoolsCrvUsd)).get_dy(0, 1, 100e18);
    }

    function sellReUSD(uint256 _amountIn) public returns(uint256 _newprice){
        deal(address(stablecoin), address(this), _amountIn);
        IERC20(address(stablecoin)).forceApprove(address(swapPoolsCrvUsd), type(uint256).max);
        ICurveExchange(address(swapPoolsCrvUsd)).exchange(1,0, _amountIn, 0, address(this));
        _newprice = ICurveExchange(address(swapPoolsCrvUsd)).get_dy(0, 1, 100e18);
    }

    function deployLendingPair(uint256 _protocolId, address _collateral, uint256 _stakingId) public returns(ResupplyPair p){
        return deployLendingPairAs(address(core), _protocolId, _collateral, _stakingId);
    }

    function deployLendingPairAs(address _deployer, uint256 _protocolId, address _collateral, uint256 _stakingId) public returns(ResupplyPair p){
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
            _protocolId == 0 ? Constants.Mainnet.CONVEX_BOOSTER : address(0),
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

    function deployCurveLendingVaultAndGauge(
        address _collateral
    ) public returns(address vault, address gauge, uint256 convexPoolId){
        // default values taken from https://etherscan.io/tx/0xe1d3e1c4fef7753e5fff72dfb96861e0fec455d17ebfce04a2858b9169c462b7
        vault = ICurveOneWayLendingFactory(Constants.Mainnet.CURVE_ONE_WAY_LENDING_FACTORY).create(
            Constants.Mainnet.CRVUSD_ERC20, //borrowed token
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
        gauge = ICurveFactory(Constants.Mainnet.CURVE_ONE_WAY_LENDING_FACTORY).deploy_gauge(_vault);
        ICurveGaugeController gaugeController = ICurveGaugeController(Constants.Mainnet.CURVE_GAUGE_CONTROLLER);
        // We need to put some weight on this gauge via gauge controller, so we lock some CRV
        deal(Constants.Mainnet.CRV_ERC20, address(this), 1_000_000e18);
        IERC20(Constants.Mainnet.CRV_ERC20).approve(Constants.Mainnet.CURVE_ESCROW, type(uint256).max);
        ICurveEscrow(Constants.Mainnet.CURVE_ESCROW).create_lock(1_000_000e18, block.timestamp + 200 weeks);
        vm.prank(gaugeController.admin());
        gaugeController.add_gauge(gauge, 1);
        gaugeController.vote_for_gauge_weights(gauge, 10_000);

        // Add the gauge to convex
        IConvexPoolManager(Constants.Mainnet.CONVEX_POOL_MANAGER).addPool(gauge);
        // (address lptoken, address token, address convexGauge, address crvRewards, address stash, bool shutdown) = IConvexStaking(Constants.Mainnet.CONVEX_BOOSTER).poolInfo(gauge);
        convexPoolId = IConvexStaking(Constants.Mainnet.CONVEX_BOOSTER).poolLength() - 1;
    }

    function clearPairImplementation() public {
        vm.startPrank(address(core));
        deployer.setCreationCode(hex"");
        vm.stopPrank();
    }
}