// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { Test } from "../../../lib/forge-std/src/Test.sol";
import { console } from "../../../lib/forge-std/src/console.sol";
// import { Test } from "../../../lib/forge-std/src/Test.sol";
// import { console } from "../../../lib/forge-std/src/console.sol";
import "src/interfaces/IStableSwap.sol";
import "src/interfaces/IVariableInterestRateV2.sol";
import "src/interfaces/IWstEth.sol";
import "src/interfaces/IOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "src/protocol/fraxlend/FraxlendPairConstants.sol";
import "src/protocol/BasicVaultOracle.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { StableCoin } from "src/protocol/StableCoin.sol";
import { InsurancePool } from "src/protocol/InsurancePool.sol";
import { SimpleRewardStreamer } from "src/protocol/SimpleRewardStreamer.sol";
import { FeeDeposit } from "src/protocol/FeeDeposit.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import "src/Constants.sol" as Constants;

import { Core } from "../../src/dao/Core.sol";
import { Voter } from "../../src/dao/Voter.sol";
import { MockToken } from "../mocks/MockToken.sol";

struct CurrentRateInfo {
        uint32 lastBlock;
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint256 lastPrice;
        uint256 lastShares;
    }

contract ProtocolSetup is
    FraxlendPairConstants,
    Test
{
    // using OracleHelper for AggregatorV3Interface;
    using SafeCast for uint256;

    // contracts
    ResupplyPair public pair;
    ResupplyPairDeployer public deployer;
    ResupplyRegistry public registry;
    Core public core;
    MockToken public stakingToken;
    StableCoin public stableToken;

    InterestRateCalculator public rateContract;
    IOracle public oracle;

    InsurancePool public insurancePool;
    SimpleRewardStreamer public ipStableStream;
    SimpleRewardStreamer public ipEmissionStream;
    SimpleRewardStreamer public pairEmissionStream;
    FeeDeposit public feeDeposit;
    FeeDepositController public feeDepositController;
    RedemptionHandler public redemptionHandler;
    LiquidationHandler public liquidationHandler;
    RewardHandler public rewardHandler;
    SimpleReceiver public emissionReceiver;


    uint256 mainnetFork;

    IERC20 public fraxToken;
    IERC20 public crvUsdToken;

    IERC20 public asset;
    IERC20 public collateral;
    
    uint256 public uniqueId;

    struct UserAccounting {
        address _address;
        uint256 borrowShares;
        uint256 borrowAmountFalse;
        uint256 borrowAmountTrue;
        uint256 collateralBalance;
        uint256 balanceOfAsset;
        uint256 balanceOfCollateral;
    }

    struct PairAccounting {
        address pairAddress;
        uint256 claimableFees;
        uint128 totalBorrowAmount;
        uint128 totalBorrowShares;
        uint256 totalCollateral;
        uint256 balanceOfAsset;
        uint256 balanceOfCollateral;
        uint128 assetShares;
        uint128 assetAmountFalse;
        uint128 assetAmountTrue;
        uint256 collateralBalance;
    }

    PairAccounting public initial;
    PairAccounting public final_;
    PairAccounting public net;

    // Users
    address[] public users = [vm.addr(1), vm.addr(2), vm.addr(3), vm.addr(4), vm.addr(5)];
    address tempGov = address(987);

    // Deployer constants
    uint256 internal constant DEFAULT_MAX_LTV = 95_000; // 75% with 1e5 precision
    uint256 internal constant DEFAULT_LIQ_FEE = 500; // 5% with 1e5 precision
    uint256 internal constant DEFAULT_BORROW_LIMIT = 5_000_000 * 1e18;
    uint256 internal constant DEFAULT_MINT_FEE = 0; //1e5 prevision
    uint256 internal constant DEFAULT_PROTOCOL_REDEMPTION_FEE = 1e18 / 2; //half
    uint64 internal constant FIFTY_BPS = 158_247_046;
    uint64 internal constant ONE_PERCENT = FIFTY_BPS * 2;
    uint64 internal constant ONE_BPS = FIFTY_BPS / 50;

    // Interest Helpers
    uint256 internal constant ONE_PERCENT_ANNUAL_RATE = 315_315_588;

    function setUp() public virtual {
        setUpCore();
        deployBaseContracts();
        deployAuxContracts();
    }

    // ============================================================================================
    // Setup / Initial Environment Helpers
    // ============================================================================================

    function setUpCore() public virtual {
        mainnetFork = vm.createSelectFork(vm.envString("MAINNET_URL"));
        // Deploy the mock factory first for deterministic location
        stakingToken = new MockToken("GovToken", "GOV");
        
        core = Core(
            address(
                new Core(tempGov, 1 weeks)
            )
        );

        stableToken = new StableCoin(address(core));

        vm.startPrank(users[0]);
        stakingToken.mint(users[0], 1_000_000 * 10 ** 18);
        vm.stopPrank();

        // label all the used addresses for traces
        vm.label(address(stakingToken), "Gov Token");
        vm.label(address(tempGov), "Temp Gov");
        vm.label(address(core), "Core");
    }
    /// @notice The ```deployNonDynamicExternalContracts``` function deploys all contracts other than the pairs using default values
    /// @dev
    function deployBaseContracts() public {

        registry = new ResupplyRegistry(address(core), address(stableToken), address(stakingToken));
        deployer = new ResupplyPairDeployer(
            address(registry),
            address(stakingToken),
            address(Constants.Mainnet.CONVEX_DEPLOYER),
            address(core)
        );
        
        vm.startPrank(address(core));
        deployer.setCreationCode(type(ResupplyPair).creationCode);
        stableToken.setOperator(address(registry),true);
        registry.setTreasury(address(users[1]));
        registry.setStaker(address(users[1]));
        vm.stopPrank();

        rateContract = new InterestRateCalculator(
            "suffix",
            634_195_840,//(2 * 1e16) / 365 / 86400, //2% todo check
            2
        );

        oracle = IOracle(
            address(
                new BasicVaultOracle(
                    "Basic Vault Oracle"
                )
            )
        );

        //default asset/collateral
        collateral = IERC20(Constants.Mainnet.FRAXLEND_SFRXETH_FRAX);
        fraxToken = IERC20(Constants.Mainnet.FRAX_ERC20);
        crvUsdToken = IERC20(Constants.Mainnet.CURVE_USD_ERC20);
    }

    function deployAuxContracts() public {
        address[] memory rewards = new address[](3);
        rewards[0] = address(stakingToken);
        rewards[1] = address(fraxToken);
        rewards[2] = address(crvUsdToken);
        insurancePool = new InsurancePool(
            address(core), //core
            address(stableToken),
            rewards,
            address(registry));

        //seed insurance pool
        stableToken.transfer(address(insurancePool),1e18);
        
        ipStableStream = new SimpleRewardStreamer(
            address(stableToken),
            address(registry),
            address(core), //core
            address(insurancePool));

        ipEmissionStream = new SimpleRewardStreamer(
            address(stakingToken),
            address(registry),
            address(core), //core
            address(insurancePool));

        //todo queue rewards to pools

        pairEmissionStream = new SimpleRewardStreamer(
            address(stakingToken),
            address(registry),
            address(core), //core
            address(0));

        feeDeposit = new FeeDeposit(
             address(core), //core
             address(registry),
             address(stableToken)
             );
        feeDepositController = new FeeDepositController(
            address(core), //core
            address(registry),
            address(feeDeposit),
            1500,
            500
            );
        //attach fee deposit controller to fee deposit
        vm.startPrank(address(core));
        feeDeposit.setOperator(address(feeDepositController));
        vm.stopPrank();

        redemptionHandler = new RedemptionHandler(
            address(core),//core
            address(registry),
            address(stableToken)
            );

        liquidationHandler = new LiquidationHandler(
            address(core),//core
            address(registry),
            address(insurancePool)
            );

        rewardHandler = new RewardHandler(
            address(core),//core
            address(registry),
            address(insurancePool),
            address(emissionReceiver),
            address(pairEmissionStream),
            address(ipEmissionStream),
            address(ipStableStream)
            );

        vm.startPrank(address(core));
        registry.setLiquidationHandler(address(liquidationHandler));
        registry.setFeeDeposit(address(feeDeposit));
        registry.setRedeemer(address(redemptionHandler));
        registry.setInsurancePool(address(insurancePool));
        registry.setRewardHandler(address(rewardHandler));
        vm.stopPrank();
    }

    /// @notice The ```defaultSetUp``` function provides a full default deployment environment for testing
    function defaultSetUp() public virtual {
        setUpCore();
        deployBaseContracts();
        deployAuxContracts();

        // faucetFunds(address(Constants.Mainnet.CURVE_USD_ERC20),100_000 * 10 ** 18,users[0]);
        deal(address(fraxToken), users[0], 100_000 * 10 ** 18);
        deal(address(crvUsdToken), users[0], 100_000 * 10 ** 18);

        console.log("======================================");
        console.log("    Base Contracts     ");
        console.log("======================================");
        console.log("Registry: ", address(registry));
        console.log("Deployer: ", address(deployer));
        console.log("govToken: ", address(stakingToken));
        console.log("stableToken: ", address(stableToken));
        console.log("insurancePool: ", address(insurancePool));
        console.log("ipStableStream: ", address(ipStableStream));
        console.log("pairEmissionStream: ", address(pairEmissionStream));
        console.log("feeDeposit: ", address(feeDeposit));
        console.log("feeDepositController: ", address(feeDepositController));
        console.log("redemptionHandler: ", address(redemptionHandler));
        console.log("liquidationHandler: ", address(liquidationHandler));
        console.log("rewardHandler: ", address(rewardHandler));
        console.log("emissionReceiver: ", address(emissionReceiver));
        console.log("======================================");
        console.log("balance of frax: ", fraxToken.balanceOf(users[0]));
        console.log("balance of crvusd: ", crvUsdToken.balanceOf(users[0]));
    }

    // ============================================================================================
    // Deployment Helpers
    // ============================================================================================

    /// @notice The ```deployFraxlendPublic``` function helps deploy Fraxlend public pairs with default config
    function deployDefaultLendingPairs() public{
        deployLendingPair(address(Constants.Mainnet.FRAXLEND_SFRXETH_FRAX), address(0), 0);
        deployLendingPair(address(Constants.Mainnet.CURVELEND_SFRAX_CRVUSD), address(Constants.Mainnet.CONVEX_BOOSTER), uint256(Constants.Mainnet.CURVELEND_SFRAX_CRVUSD_ID));
    }

    function deployLendingPair(address _collateral, address _staking, uint256 _stakingId) public returns(ResupplyPair){
        vm.startPrank(deployer.owner());

        address _pairAddress = deployer.deploy(
            abi.encode(
                _collateral,
                address(oracle),
                address(rateContract),
                DEFAULT_MAX_LTV, //max ltv 75%
                DEFAULT_BORROW_LIMIT,
                DEFAULT_LIQ_FEE,
                DEFAULT_MINT_FEE,
                DEFAULT_PROTOCOL_REDEMPTION_FEE
            ),
            _staking,
            _stakingId,
            uniqueId
        );

        uniqueId += 1;
        pair = ResupplyPair(_pairAddress);
        vm.stopPrank();

        vm.startPrank(address(core));
        registry.addPair(_pairAddress);
        vm.stopPrank();

        // startHoax(Constants.Mainnet.COMPTROLLER_ADDRESS);
        // pair.setSwapper(Constants.Mainnet.UNIV2_ROUTER, true);
        // vm.stopPrank();

        return pair;
    }
}
