// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../helpers/Helpers.sol";
import "src/interfaces/IStableSwap.sol";
import "src/interfaces/IVariableInterestRateV2.sol";
import "src/interfaces/IWstEth.sol";
import "src/interfaces/IOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "src/protocol/fraxlend/FraxlendPairConstants.sol";
import "src/protocol/BasicVaultOracle.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { Stablecoin } from "src/protocol/StableCoin.sol";
import { InsurancePool } from "src/protocol/InsurancePool.sol";
import { SimpleRewardStreamer } from "src/protocol/SimpleRewardStreamer.sol";
import { FeeDeposit } from "src/protocol/FeeDeposit.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { EmissionsController } from "../../../src/dao/emissions/EmissionsController.sol";
import "src/Constants.sol" as Constants;
import "frax-std/FraxTest.sol";

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

contract BasePairTest is
    FraxlendPairConstants,
    TestHelper,
    // Constants.Helper,
    FraxTest
{
    using stdStorage for StdStorage;
    // using OracleHelper for AggregatorV3Interface;
    using SafeCast for uint256;
    using Strings for uint256;
    using ResupplyPairTestHelper for ResupplyPair;
    using NumberFormat for *;
    using StringsHelper for *;

    // contracts
    ResupplyPairDeployer public deployer;
    ResupplyRegistry public registry;
    Core public core;
    MockToken public stakingToken;
    Stablecoin public stablecoin;
    EmissionsController public emissionsController;

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

        stablecoin = new Stablecoin(address(core));

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

        registry = new ResupplyRegistry(address(core), address(stablecoin), address(stakingToken));
        deployer = new ResupplyPairDeployer(
            address(registry),
            address(stakingToken),
            address(Constants.Mainnet.CONVEX_DEPLOYER),
            address(core)
        );
        
        vm.startPrank(address(core));
        deployer.setCreationCode(type(ResupplyPair).creationCode);
        stablecoin.setOperator(address(registry),true);
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

        emissionsController = new EmissionsController(
            address(core), 
            address(stakingToken), 
            getEmissionsSchedule(), 
            3,      // epochs per
            2e16,   // tail rate
            0       // Bootstrap epochs
        );
    }

    function getEmissionsSchedule() public view returns (uint256[] memory) {
        uint256[] memory schedule = new uint256[](5);
        schedule[0] = 2 * 10 ** 16;     // 2%
        schedule[1] = 4 * 10 ** 16;     // 4%
        schedule[2] = 6 * 10 ** 16;     // 6%
        schedule[3] = 8 * 10 ** 16;     // 8%
        schedule[4] = 10 * 10 ** 16;    // 10%
        return schedule;
    }

    function deployAuxContracts() public {
        address[] memory rewards = new address[](3);
        rewards[0] = address(stakingToken);
        rewards[1] = address(fraxToken);
        rewards[2] = address(crvUsdToken);
        insurancePool = new InsurancePool(
            address(core), //core
            address(stablecoin),
            rewards,
            address(registry));

        //seed insurance pool
        stablecoin.transfer(address(insurancePool),1e18);
        
        ipStableStream = new SimpleRewardStreamer(
            address(stablecoin),
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
             address(stablecoin)
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
            address(stablecoin)
            );

        liquidationHandler = new LiquidationHandler(
            address(core),//core
            address(registry),
            address(insurancePool)
            );

        // emissionReceiver = new SimpleReceiver//TODO
        emissionReceiver = new SimpleReceiver(
            address(core),
            address(emissionsController)
            );
        vm.startPrank(address(core));
        emissionsController.registerReceiver(address(emissionReceiver));
        vm.stopPrank();

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
        emissionReceiver.setApprovedClaimer(address(rewardHandler), true);
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
        faucetFunds(fraxToken,100_000 * 10 ** 18,users[0]);
        faucetFunds(crvUsdToken,100_000 * 10 ** 18,users[0]);

        console.log("======================================");
        console.log("    Base Contracts     ");
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

    function deployLendingPair(address _collateral, address _staking, uint256 _stakingId) public returns(ResupplyPair _pair){
        vm.startPrank(address(Constants.Mainnet.CONVEX_DEPLOYER));

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
        _pair = ResupplyPair(_pairAddress);
        vm.stopPrank();

        vm.startPrank(address(core));
        registry.addPair(_pairAddress);
        vm.stopPrank();

        // startHoax(Constants.Mainnet.COMPTROLLER_ADDRESS);
        // _pair.setSwapper(Constants.Mainnet.UNIV2_ROUTER, true);
        // vm.stopPrank();
    }


    // ============================================================================================
    // Snapshots
    // ============================================================================================

    function initialUserAccountingSnapshot(
        ResupplyPair _pair,
        address _userAddress
    ) public returns (UserAccounting memory) {
        (uint256 _borrowShares, uint256 _collateralBalance) = _pair.getUserSnapshot(
            _userAddress
        );
        return
            UserAccounting({
                _address: _userAddress,
                borrowShares: _borrowShares,
                borrowAmountFalse: toBorrowAmount(_pair, _borrowShares, false),
                borrowAmountTrue: toBorrowAmount(_pair, _borrowShares, true),
                collateralBalance: _collateralBalance,
                balanceOfAsset: stablecoin.balanceOf(_userAddress),
                balanceOfCollateral: IERC20(address(_pair.collateralContract())).balanceOf(_userAddress)
            });
    }

    function finalUserAccountingSnapshot(
        ResupplyPair _pair,
        UserAccounting memory _initial
    ) public returns (UserAccounting memory _final, UserAccounting memory _net) {
        address _userAddress = _initial._address;
        (uint256 _borrowShares, uint256 _collateralBalance) = _pair.getUserSnapshot(
            _userAddress
        );
        _final = UserAccounting({
            _address: _userAddress,
            borrowShares: _borrowShares,
            borrowAmountFalse: toBorrowAmount(_pair, _borrowShares, false),
            borrowAmountTrue: toBorrowAmount(_pair, _borrowShares, true),
            collateralBalance: _collateralBalance,
            balanceOfAsset: stablecoin.balanceOf(_userAddress),
            balanceOfCollateral: IERC20(address(_pair.collateralContract())).balanceOf(_userAddress)
        });
        _net = UserAccounting({
            _address: _userAddress,
            borrowShares: stdMath.delta(_initial.borrowShares, _final.borrowShares),
            borrowAmountFalse: stdMath.delta(_initial.borrowAmountFalse, _final.borrowAmountFalse),
            borrowAmountTrue: stdMath.delta(_initial.borrowAmountTrue, _final.borrowAmountTrue),
            collateralBalance: stdMath.delta(_initial.collateralBalance, _final.collateralBalance),
            balanceOfAsset: stdMath.delta(_initial.balanceOfAsset, _final.balanceOfAsset),
            balanceOfCollateral: stdMath.delta(_initial.balanceOfCollateral, _final.balanceOfCollateral)
        });
    }

    function takeInitialAccountingSnapshot(
        ResupplyPair _pair
    ) internal returns (PairAccounting memory _initial) {
        address _pairAddress = address(_pair);
        IERC20 _collateral = _pair.collateralContract();

        (
            uint256 _claimableFees,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        ) = _pair.__getPairAccounting();
        _initial.pairAddress = _pairAddress;
        _initial.claimableFees = _claimableFees;
        _initial.totalBorrowAmount = _totalBorrowAmount;
        _initial.totalBorrowShares = _totalBorrowShares;
        _initial.totalCollateral = _totalCollateral;
        _initial.balanceOfAsset = stablecoin.balanceOf(_pairAddress);
        _initial.balanceOfCollateral = _collateral.balanceOf(_pairAddress);
        _initial.collateralBalance = _pair.userCollateralBalance(_pairAddress);
    }

    function takeFinalAccountingSnapshot(
        PairAccounting memory _initial
    ) internal returns (PairAccounting memory _final, PairAccounting memory _net) {
        address _pairAddress = _initial.pairAddress;
        ResupplyPair _pair = ResupplyPair(_pairAddress);
        IERC20 _collateral = _pair.collateralContract();

        (
            uint256 _claimableFees,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        ) = _pair.getPairAccounting();
        // Sorry for mutation syntax
        _final.pairAddress = _pairAddress;
        _final.claimableFees = _claimableFees;
        _final.totalBorrowAmount = _totalBorrowAmount;
        _final.totalBorrowShares = _totalBorrowShares;
        _final.totalCollateral = _totalCollateral;
        _final.balanceOfAsset = stablecoin.balanceOf(_pairAddress);
        _final.balanceOfCollateral = _collateral.balanceOf(_pairAddress);
        _final.collateralBalance = _pair.userCollateralBalance(_pairAddress);

        _net.pairAddress = _pairAddress;
        _net.claimableFees = stdMath.delta(_final.claimableFees, _initial.claimableFees).toUint128();
        _net.totalBorrowAmount = stdMath.delta(_final.totalBorrowAmount, _initial.totalBorrowAmount).toUint128();
        _net.totalBorrowShares = stdMath.delta(_final.totalBorrowShares, _initial.totalBorrowShares).toUint128();
        _net.totalCollateral = stdMath.delta(_final.totalCollateral, _initial.totalCollateral);
        _net.balanceOfAsset = stdMath.delta(_final.balanceOfAsset, _initial.balanceOfAsset);
        _net.balanceOfCollateral = stdMath.delta(_final.balanceOfCollateral, _initial.balanceOfCollateral);
        _net.collateralBalance = stdMath.delta(_final.collateralBalance, _initial.collateralBalance).toUint128();
    }

    function assertPairAccountingCorrect(ResupplyPair _pair) public {
        // require(1 == 2, "This is a test function with a very long reason string that should be truncated");
        uint256 _totalUserBorrowShares = _pair.userBorrowShares(address(_pair));
        uint256 _totalUserCollateralBalance = _pair.userCollateralBalance(address(_pair));
       // uint256 _totalUserAssetShares = _pair.balanceOf(address(pair));

        for (uint256 i = 0; i < users.length; i++) {
            _totalUserBorrowShares += _pair.userBorrowShares(users[i]);
            _totalUserCollateralBalance += _pair.userCollateralBalance(users[i]);
            // _totalUserAssetShares += _pair.balanceOf(users[i]);
        }

        (uint128 _pairTotalBorrowAmount, uint128 _pairTotalBorrowShares) = _pair.totalBorrow();
        // (uint128 _pairTotalAssetAmount, uint128 _pairTotalAssetShares) = _pair.totalAsset();
        assertEq(
            _totalUserBorrowShares,
            _pairTotalBorrowShares,
            "Sum of users borrow shares equals accounting borrow shares"
        );
        assertEq(
            _totalUserCollateralBalance,
            _pair.totalCollateral(),
            "Sum of users collateral balance equals total collateral accounting"
        );
        // assertEq(
        //     _totalUserAssetShares,
        //     _pairTotalAssetShares,
        //     "Sum of users asset shares equals total asset shares accounting"
        // );
        assertEq(
            _pair.totalCollateral(),
            collateral.balanceOf(address(_pair)),
            "Total collateral accounting matches collateral.balanceOf"
        );
        // assertEq(
        //     _pairTotalAssetAmount - _pairTotalBorrowAmount,
        //     asset.balanceOf(address(_pair)),
        //     "Total collateral accounting matches collateral.balanceOf"
        // );
    }

    function assertUnwind(ResupplyPair _pair) public {
        for (uint256 i = 0; i < users.length; i++) {
            address _user = users[i];
            startHoax(_user);
            uint256 _borrowShares = _pair.userBorrowShares(_user);
            uint256 _borrowAmount = _pair.toBorrowAmount(_borrowShares, true, false);
            uint256 _collateralBalance = _pair.userCollateralBalance(_user);
            faucetFunds(stablecoin, _borrowAmount, _user);
            stablecoin.approve(address(_pair), _borrowAmount);
            _pair.repay(_borrowShares, _user);
            _pair.removeCollateral(_collateralBalance, _user);
            vm.stopPrank();
        }

        //todo
        // for (uint256 i = 0; i < users.length; i++) {
        //     address _user = users[i];
        //     startHoax(_user);
        //     uint256 _shares = _pair.balanceOf(_user);
        //     _pair.redeem(_shares, _user, _user);
        //     vm.stopPrank();
        // }
    }

    // ============================================================================================
    // Pair View Helpers
    // ============================================================================================

    function toBorrowAmount(
        ResupplyPair _pair,
        uint256 _shares,
        bool roundup
    ) public view returns (uint256 _amount) {
        (uint256 _amountTotal, uint256 _sharesTotal) = _pair.totalBorrow();
        _amount = toBorrowAmount(_amountTotal, _sharesTotal, _shares, roundup);
    }

    // helper to convert borrows shares to amount
    function toBorrowAmount(
        uint256 _amountTotal,
        uint256 _sharesTotal,
        uint256 _shares,
        bool roundup
    ) public pure returns (uint256 _amount) {
        if (_sharesTotal == 0) {
            _amount = _shares;
        } else {
            _amount = (_shares * _amountTotal) / _sharesTotal;
            if (roundup && (_amount * _sharesTotal) / _amountTotal < _shares) {
                _amount++;
            }
        }
    }

    // helper to convert borrow amount to shares
    function toBorrowShares(ResupplyPair _pair, uint256 _amount, bool roundup) public view returns (uint256 _shares) {
        (uint256 _amountTotal, uint256 _sharesTotal) = _pair.totalBorrow();
        _shares = toBorrowShares(_amountTotal, _sharesTotal, _amount, roundup);
    }

    // helper to convert borrow amount to shares
    function toBorrowShares(
        uint256 _amountTotal,
        uint256 _sharesTotal,
        uint256 _amount,
        bool roundup
    ) public pure returns (uint256 _shares) {
        if (_amountTotal == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount * _sharesTotal) / _amountTotal;
            if (roundup && (_shares * _amountTotal) / _sharesTotal < _amount) {
                _shares++;
            }
        }
    }

    function getUtilization(ResupplyPair _pair) internal view returns (uint256 _utilization) {
        (uint256 _borrowAmount, ) = _pair.totalBorrow();
        uint256 _borrowLimit = _pair.borrowLimit();
        _utilization = (_borrowAmount * EXCHANGE_PRECISION) / _borrowLimit;
    }

    function ratePerSec(ResupplyPair _pair) internal view returns (uint64 _ratePerSec) {
        (, , _ratePerSec,, ) = _pair.currentRateInfo();
    }

    function getCollateralAmount(
        uint256 _borrowAmount,
        uint256 _exchangeRate,
        uint256 _targetLTV
    ) internal pure returns (uint256 _collateralAmount) {
        _collateralAmount = (_borrowAmount * _exchangeRate * LTV_PRECISION) / (_targetLTV * EXCHANGE_PRECISION);
    }

    // ============================================================================================
    // Pair Action Helpers
    // ============================================================================================

    // helper to faucet funds to ERC20 contracts if no users give to all
    function faucetFunds(IERC20 _contract, uint256 _amount) internal {
        uint256 _length = users.length; // gas savings, good habit
        for (uint256 i = 0; i < _length; i++) {
            faucetFunds(_contract, _amount, users[i]);
        }
    }

    struct DepositAction {
        address user;
        uint256 amount;
    }

    struct MintAction {
        address user;
        uint256 shares;
    }

    // Borrowing

    struct BorrowAction {
        address user;
        uint256 borrowAmount;
        uint256 collateralAmount;
    }

    function _preBorrowFaucetApprove(ResupplyPair _pair, BorrowAction memory _borrowAction) internal {
        IERC20 _collateral = _pair.collateralContract();
        faucetFunds(_collateral, _borrowAction.collateralAmount, _borrowAction.user);
        _collateral.approve(address(_pair), _borrowAction.collateralAmount);
    }

    function borrowToken(
        ResupplyPair _pair,
        uint256 _amountToBorrow,
        uint256 _collateralAmount,
        address _user
    ) internal returns (uint256 _finalShares, uint256 _finalCollateralBalance) {
        vm.startPrank(_user);
        collateral.approve(address(_pair), _collateralAmount);
        _pair.borrow(uint128(_amountToBorrow), _collateralAmount, _user);
        _finalShares = _pair.userBorrowShares(_user);
        _finalCollateralBalance = _pair.userCollateralBalance(_user);
        vm.stopPrank();
    }

    function borrowTokenWithFaucet(
        ResupplyPair _pair,
        BorrowAction memory _borrowAction
    ) internal returns (uint256 _finalShares, uint256 _finalCollateralBalance) {
        faucetFunds(_pair.collateralContract(), _borrowAction.collateralAmount, _borrowAction.user);
        (_finalShares, _finalCollateralBalance) = borrowToken(
            _pair,
            _borrowAction.borrowAmount,
            _borrowAction.collateralAmount,
            _borrowAction.user
        );
    }

    // Repaying
    struct RepayAction {
        ResupplyPair pair;
        address user;
        uint256 shares;
    }

    // helper to approve and repay in one step, should have called addInterest before hand

    function repayToken(
        ResupplyPair _pair,
        uint256 _sharesToRepay,
        address _user
    ) internal returns (uint256 _finalShares) {
        uint256 _amountToApprove = toBorrowAmount(_pair, _sharesToRepay, true);
        asset.approve(address(_pair), _amountToApprove);
        _pair.repay(_sharesToRepay, _user);
        _finalShares = _pair.userBorrowShares(_user);
    }

    function repayTokenWithFaucet(
        ResupplyPair _pair,
        uint256 _sharesToRepay,
        address _user
    ) internal returns (uint256 _finalShares) {
        faucetFunds(stablecoin, 2 * _sharesToRepay, _user);
        _finalShares = repayToken(_pair, _sharesToRepay, _user);
    }

    // helper to move forward multiple blocks and add interest each time
    function addInterestAndMineBulk(ResupplyPair _pair, uint256 _blocks) internal returns (uint256 _sumOfInt) {
        _sumOfInt = 0;
        for (uint256 i = 0; i < _blocks; i++) {
            mineOneBlock();
            (uint256 _interestEarned,,,) = _pair.addInterest(false);

            _sumOfInt += _interestEarned;
        }
    }
}
