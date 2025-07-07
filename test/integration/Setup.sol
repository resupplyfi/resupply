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

// Incentive Contracts
import { ISimpleRewardStreamer } from "src/interfaces/ISimpleRewardStreamer.sol";
import { IFeeDeposit } from "src/interfaces/IFeeDeposit.sol";
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { ISimpleReceiver } from "src/interfaces/ISimpleReceiver.sol";
import { ISimpleReceiverFactory } from "src/interfaces/ISimpleReceiverFactory.sol";

// Others
import { ICurveExchange } from "src/interfaces/ICurveExchange.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



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
    IResupplyPairDeployer public deployer = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER);
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

    constructor() {}

    function setUp() public virtual {}

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
}