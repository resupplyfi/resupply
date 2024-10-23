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
import "src/protocol/fraxlend/FraxlendPairAccessControlErrors.sol";
import "src/protocol/BasicVaultOracle.sol";
import { RelendPairDeployer } from "src/protocol/RelendPairDeployer.sol";
import { RelendPairRegistry } from "src/protocol/RelendPairRegistry.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { FraxlendPair } from "src/protocol/fraxlend/FraxlendPair.sol";
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
    FraxlendPairAccessControlErrors,
    TestHelper,
    // Constants.Helper,
    FraxTest
{
    using stdStorage for StdStorage;
    // using OracleHelper for AggregatorV3Interface;
    using SafeCast for uint256;
    using Strings for uint256;
    using RelendPairTestHelper for FraxlendPair;
    using NumberFormat for *;
    using StringsHelper for *;

    // contracts
    FraxlendPair public pair;
    RelendPairDeployer public deployer;
    RelendPairRegistry public pairRegistry;
    Core public core;
    MockToken public stakingToken;
    MockToken public stableToken;

    uint256 mainnetFork;

    IERC20 public asset;
    IERC20 public collateral;
    InterestRateCalculator public rateContract;

    IOracle public oracle;
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
        address fraxlendPairAddress;
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
    // uint256 internal constant DEFAULT_PROTOCOL_LIQ_FEE = 200; // 2% of fee total collateral
    // uint64 internal constant DEFAULT_MIN_INTEREST = 158_247_046;
    // uint64 internal constant DEFAULT_MAX_INTEREST = 146_248_476_607;
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
        stableToken = new MockToken("StableToken", "STABLE");

        core = Core(
            address(
                new Core(tempGov, 1 weeks)
            )
        );

        vm.startPrank(users[0]);
        stakingToken.mint(users[0], 1_000_000 * 10 ** 18);
        stableToken.mint(users[0], 1_000_000 * 10 ** 18);
        vm.stopPrank();

        // label all the used addresses for traces
        vm.label(address(stakingToken), "Gov Token");
        vm.label(address(tempGov), "Temp Gov");
        vm.label(address(core), "Core");
    }
    /// @notice The ```deployNonDynamicExternalContracts``` function deploys all contracts other than the pairs using default values
    /// @dev
    function deployBaseContracts() public {

        pairRegistry = new RelendPairRegistry(address(stableToken),address(core));
        deployer = new RelendPairDeployer(
            address(pairRegistry),
            address(stakingToken),
            address(Constants.Mainnet.CONVEX_DEPLOYER),
            address(core)
        );
        
        vm.startPrank(address(core));
        deployer.setCreationCode(type(FraxlendPair).creationCode);
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
        collateral = IERC20(Constants.Mainnet.FRAXLEND_SFRAX_FRAX);
        asset = IERC20(Constants.Mainnet.FRAX_ERC20);
    }

    /// @notice The ```defaultSetUp``` function provides a full default deployment environment for testing
    function defaultSetUp() public virtual {
        setUpCore();
        deployBaseContracts();

        console.log("======================================");
        console.log("    Base Contracts     ");
        console.log("======================================");
        console.log("Registry: ", address(pairRegistry));
        console.log("Deployer: ", address(deployer));
        console.log("govToken: ", address(stakingToken));
        console.log("stableToken: ", address(stableToken));
    }

    // ============================================================================================
    // Deployment Helpers
    // ============================================================================================

    /// @notice The ```deployFraxlendPublic``` function helps deploy Fraxlend public pairs with default config
    function deployDefaultLendingPair() public returns(FraxlendPair) {
        return deployLendingPair(address(asset), address(collateral), address(0), 0);
    }

    function deployLendingPair(address _asset, address _collateral, address _staking, uint256 _stakingId) public returns(FraxlendPair){
        vm.startPrank(address(Constants.Mainnet.CONVEX_DEPLOYER));

        address _pairAddress = deployer.deploy(
            abi.encode(
                _asset,
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
        pair = FraxlendPair(_pairAddress);
        vm.stopPrank();

        vm.startPrank(address(core));
        // pairRegistry.addPair(_pairAddress);
        vm.stopPrank();

        // startHoax(Constants.Mainnet.COMPTROLLER_ADDRESS);
        // pair.setSwapper(Constants.Mainnet.UNIV2_ROUTER, true);
        // vm.stopPrank();

        return pair;
    }

    // function _encodeConfigData(
    //     address _rateContract,
    //     uint64 _fullUtilizationRate,
    //     uint256 _maxLTV,
    //     uint256 _liquidationFee,
    //     uint256 _protocolLiquidationFee
    // ) internal view returns (bytes memory _configData) {
    //     _configData = abi.encode(
    //         address(asset),
    //         address(collateral),
    //         address(oracle),
    //         uint32(5e3),
    //         address(_rateContract),
    //         _fullUtilizationRate,
    //         _maxLTV, //75%
    //         _liquidationFee,
    //         _protocolLiquidationFee
    //     );
    // }

    // ============================================================================================
    // Snapshots
    // ============================================================================================

    function initialUserAccountingSnapshot(
        FraxlendPair _relendPair,
        address _userAddress
    ) public returns (UserAccounting memory) {
        (uint256 _borrowShares, uint256 _collateralBalance) = _relendPair.getUserSnapshot(
            _userAddress
        );
        return
            UserAccounting({
                _address: _userAddress,
                borrowShares: _borrowShares,
                borrowAmountFalse: toBorrowAmount(_relendPair, _borrowShares, false),
                borrowAmountTrue: toBorrowAmount(_relendPair, _borrowShares, true),
                collateralBalance: _collateralBalance,
                balanceOfAsset: IERC20(_relendPair.asset()).balanceOf(_userAddress),
                balanceOfCollateral: IERC20(address(_relendPair.collateralContract())).balanceOf(_userAddress)
            });
    }

    function finalUserAccountingSnapshot(
        FraxlendPair _relendPair,
        UserAccounting memory _initial
    ) public returns (UserAccounting memory _final, UserAccounting memory _net) {
        address _userAddress = _initial._address;
        (uint256 _borrowShares, uint256 _collateralBalance) = _relendPair.getUserSnapshot(
            _userAddress
        );
        _final = UserAccounting({
            _address: _userAddress,
            borrowShares: _borrowShares,
            borrowAmountFalse: toBorrowAmount(_relendPair, _borrowShares, false),
            borrowAmountTrue: toBorrowAmount(_relendPair, _borrowShares, true),
            collateralBalance: _collateralBalance,
            balanceOfAsset: IERC20(_relendPair.asset()).balanceOf(_userAddress),
            balanceOfCollateral: IERC20(address(_relendPair.collateralContract())).balanceOf(_userAddress)
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
        FraxlendPair _relendPair
    ) internal returns (PairAccounting memory _initial) {
        address _fraxlendPairAddress = address(_relendPair);
        IERC20 _asset = IERC20(_relendPair.asset());
        IERC20 _collateral = _relendPair.collateralContract();

        (
            uint256 _claimableFees,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        ) = _relendPair.__getPairAccounting();
        _initial.fraxlendPairAddress = _fraxlendPairAddress;
        _initial.claimableFees = _claimableFees;
        _initial.totalBorrowAmount = _totalBorrowAmount;
        _initial.totalBorrowShares = _totalBorrowShares;
        _initial.totalCollateral = _totalCollateral;
        _initial.balanceOfAsset = _asset.balanceOf(_fraxlendPairAddress);
        _initial.balanceOfCollateral = _collateral.balanceOf(_fraxlendPairAddress);
        _initial.collateralBalance = _relendPair.userCollateralBalance(_fraxlendPairAddress);
    }

    function takeFinalAccountingSnapshot(
        PairAccounting memory _initial
    ) internal returns (PairAccounting memory _final, PairAccounting memory _net) {
        address _fraxlendPairAddress = _initial.fraxlendPairAddress;
        FraxlendPair _fraxlendPair = FraxlendPair(_fraxlendPairAddress);
        IERC20 _asset = IERC20(_fraxlendPair.asset());
        IERC20 _collateral = _fraxlendPair.collateralContract();

        (
            uint256 _claimableFees,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        ) = _fraxlendPair.getPairAccounting();
        // Sorry for mutation syntax
        _final.fraxlendPairAddress = _fraxlendPairAddress;
        _final.claimableFees = _claimableFees;
        _final.totalBorrowAmount = _totalBorrowAmount;
        _final.totalBorrowShares = _totalBorrowShares;
        _final.totalCollateral = _totalCollateral;
        _final.balanceOfAsset = _asset.balanceOf(_fraxlendPairAddress);
        _final.balanceOfCollateral = _collateral.balanceOf(_fraxlendPairAddress);
        _final.collateralBalance = _fraxlendPair.userCollateralBalance(_fraxlendPairAddress);

        _net.fraxlendPairAddress = _fraxlendPairAddress;
        _net.claimableFees = stdMath.delta(_final.claimableFees, _initial.claimableFees).toUint128();
        _net.totalBorrowAmount = stdMath.delta(_final.totalBorrowAmount, _initial.totalBorrowAmount).toUint128();
        _net.totalBorrowShares = stdMath.delta(_final.totalBorrowShares, _initial.totalBorrowShares).toUint128();
        _net.totalCollateral = stdMath.delta(_final.totalCollateral, _initial.totalCollateral);
        _net.balanceOfAsset = stdMath.delta(_final.balanceOfAsset, _initial.balanceOfAsset);
        _net.balanceOfCollateral = stdMath.delta(_final.balanceOfCollateral, _initial.balanceOfCollateral);
        _net.collateralBalance = stdMath.delta(_final.collateralBalance, _initial.collateralBalance).toUint128();
    }

    function assertPairAccountingCorrect() public {
        // require(1 == 2, "This is a test function with a very long reason string that should be truncated");
        uint256 _totalUserBorrowShares = pair.userBorrowShares(address(pair));
        uint256 _totalUserCollateralBalance = pair.userCollateralBalance(address(pair));
       // uint256 _totalUserAssetShares = pair.balanceOf(address(pair));

        for (uint256 i = 0; i < users.length; i++) {
            _totalUserBorrowShares += pair.userBorrowShares(users[i]);
            _totalUserCollateralBalance += pair.userCollateralBalance(users[i]);
            // _totalUserAssetShares += pair.balanceOf(users[i]);
        }

        (uint128 _pairTotalBorrowAmount, uint128 _pairTotalBorrowShares) = pair.totalBorrow();
        // (uint128 _pairTotalAssetAmount, uint128 _pairTotalAssetShares) = pair.totalAsset();
        assertEq(
            _totalUserBorrowShares,
            _pairTotalBorrowShares,
            "Sum of users borrow shares equals accounting borrow shares"
        );
        assertEq(
            _totalUserCollateralBalance,
            pair.totalCollateral(),
            "Sum of users collateral balance equals total collateral accounting"
        );
        // assertEq(
        //     _totalUserAssetShares,
        //     _pairTotalAssetShares,
        //     "Sum of users asset shares equals total asset shares accounting"
        // );
        assertEq(
            pair.totalCollateral(),
            collateral.balanceOf(address(pair)),
            "Total collateral accounting matches collateral.balanceOf"
        );
        // assertEq(
        //     _pairTotalAssetAmount - _pairTotalBorrowAmount,
        //     asset.balanceOf(address(pair)),
        //     "Total collateral accounting matches collateral.balanceOf"
        // );
    }

    function assertUnwind(FraxlendPair _pair) public {
        IERC20 _asset = IERC20(_pair.asset());
        for (uint256 i = 0; i < users.length; i++) {
            address _user = users[i];
            startHoax(_user);
            uint256 _borrowShares = _pair.userBorrowShares(_user);
            uint256 _borrowAmount = _pair.toBorrowAmount(_borrowShares, true, false);
            uint256 _collateralBalance = _pair.userCollateralBalance(_user);
            faucetFunds(_asset, _borrowAmount, _user);
            _asset.approve(address(_pair), _borrowAmount);
            _pair.repayAsset(_borrowShares, _user);
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

    // helper to convert assets shares to amount
    // function toAssetAmount(uint256 _shares, bool roundup) public view returns (uint256 _amount) {
    //     (uint256 _amountTotal, uint256 _sharesTotal) = pair.totalAsset();
    //     _amount = toAssetAmount(_amountTotal, _sharesTotal, _shares, roundup);
    // }

    // function toAssetAmount(
    //     FraxlendPair _fraxlendPair,
    //     uint256 _shares,
    //     bool roundup
    // ) public view returns (uint256 _amount) {
    //     (uint256 _amountTotal, uint256 _sharesTotal) = _fraxlendPair.totalAsset();
    //     _amount = toAssetAmount(_amountTotal, _sharesTotal, _shares, roundup);
    // }

    // // helper to convert assets shares to amount
    // function toAssetAmount(
    //     uint256 _amountTotal,
    //     uint256 _sharesTotal,
    //     uint256 _shares,
    //     bool roundup
    // ) public pure returns (uint256 _amount) {
    //     if (_sharesTotal == 0) {
    //         _amount = _shares;
    //     } else {
    //         _amount = (_shares * _amountTotal) / _sharesTotal;
    //         if (roundup && (_amount * _sharesTotal) / _amountTotal < _shares) {
    //             _amount++;
    //         }
    //     }
    // }

    // helper to convert borrows shares to amount
    function toBorrowAmount(uint256 _shares, bool roundup) public view returns (uint256 _amount) {
        (uint256 _amountTotal, uint256 _sharesTotal) = pair.totalBorrow();
        _amount = toBorrowAmount(_amountTotal, _sharesTotal, _shares, roundup);
    }

    function toBorrowAmount(
        FraxlendPair _fraxlendPair,
        uint256 _shares,
        bool roundup
    ) public view returns (uint256 _amount) {
        (uint256 _amountTotal, uint256 _sharesTotal) = _fraxlendPair.totalBorrow();
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

    // // helper to convert asset amount to shares
    // function toAssetShares(uint256 _amount, bool roundup) public view returns (uint256 _shares) {
    //     (uint256 _amountTotal, uint256 _sharesTotal) = pair.totalAsset();
    //     _shares = toAssetShares(_amountTotal, _sharesTotal, _amount, roundup);
    // }

    // // helper to convert asset amount to shares
    // function toAssetShares(
    //     uint256 _amountTotal,
    //     uint256 _sharesTotal,
    //     uint256 _amount,
    //     bool roundup
    // ) public pure returns (uint256 _shares) {
    //     if (_amountTotal == 0) {
    //         _shares = _amount;
    //     } else {
    //         _shares = (_amount * _sharesTotal) / _amountTotal;
    //         if (roundup && (_shares * _amountTotal) / _sharesTotal < _amount) {
    //             _shares++;
    //         }
    //     }
    // }

    // helper to convert borrow amount to shares
    function toBorrowShares(uint256 _amount, bool roundup) public view returns (uint256 _shares) {
        (uint256 _amountTotal, uint256 _sharesTotal) = pair.totalBorrow();
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

    function getUtilization() internal view returns (uint256 _utilization) {
        (uint256 _borrowAmount, ) = pair.totalBorrow();
        uint256 _borrowLimit = pair.borrowLimit();
        _utilization = (_borrowAmount * EXCHANGE_PRECISION) / _borrowLimit;
    }

    function ratePerSec(FraxlendPair _pair) internal view returns (uint64 _ratePerSec) {
        (, , _ratePerSec,, ) = _pair.currentRateInfo();
    }

    // function feeToProtocolRate(FraxlendPair _pair) internal view returns (uint64 _feeToProtocolRate) {
    //     (, _feeToProtocolRate, , , ) = _pair.currentRateInfo();
    // }

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

    // function _preMintFaucetApprove(FraxlendPair _fraxlendPair, MintAction memory _mintAction) internal {
    //     IERC20 _asset = IERC20(_fraxlendPair.asset());
    //     uint256 _amount = _fraxlendPair.previewMint(_mintAction.shares);
    //     faucetFunds(_asset, _amount, _mintAction.user);
    //     _asset.approve(address(_fraxlendPair), _amount);
    // }

    // function lendTokenViaMintWithFaucet(FraxlendPair _pair, MintAction memory _mintAction) internal returns (uint256) {
    //     startHoax(_mintAction.user);
    //     _preMintFaucetApprove(_pair, _mintAction);
    //     uint256 _amount = _pair.mint(_mintAction.shares, _mintAction.user);
    //     vm.stopPrank();
    //     return _amount;
    // }

    // function _preDepositFaucetApprove(FraxlendPair _fraxlendPair, DepositAction memory _depositAction) internal {
    //     IERC20 _asset = IERC20(_fraxlendPair.asset());
    //     faucetFunds(_asset, _depositAction.amount, _depositAction.user);
    //     _asset.approve(address(_fraxlendPair), _depositAction.amount);
    // }

    // helper to approve and lend in one step
    // function lendTokenViaDeposit(FraxlendPair _pair, DepositAction memory _depositAction) internal returns (uint256) {
    //     startHoax(_depositAction.user);
    //     IERC20(_pair.asset()).approve(address(_pair), _depositAction.amount);
    //     uint256 _shares = _pair.deposit(_depositAction.amount, _depositAction.user);
    //     vm.stopPrank();
    //     return _shares;
    // }

    // function lendTokenViaDepositWithFaucet(
    //     FraxlendPair _pair,
    //     DepositAction memory _depositAction
    // ) internal returns (uint256) {
    //     faucetFunds(IERC20(_pair.asset()), _depositAction.amount, _depositAction.user);
    //     return lendTokenViaDeposit(_pair, _depositAction);
    // }

    // Borrowing

    struct BorrowAction {
        address user;
        uint256 borrowAmount;
        uint256 collateralAmount;
    }

    function _preBorrowFaucetApprove(FraxlendPair _fraxlendPair, BorrowAction memory _borrowAction) internal {
        IERC20 _collateral = _fraxlendPair.collateralContract();
        faucetFunds(_collateral, _borrowAction.collateralAmount, _borrowAction.user);
        _collateral.approve(address(_fraxlendPair), _borrowAction.collateralAmount);
    }

    // helper to approve and lend in one step
    function borrowToken(
        uint256 _amountToBorrow,
        uint256 _collateralAmount,
        address _user
    ) internal returns (uint256 _finalShares, uint256 _finalCollateralBalance) {
        (_finalShares, _finalCollateralBalance) = borrowToken(pair, _amountToBorrow, _collateralAmount, _user);
    }

    function borrowToken(
        FraxlendPair _pair,
        uint256 _amountToBorrow,
        uint256 _collateralAmount,
        address _user
    ) internal returns (uint256 _finalShares, uint256 _finalCollateralBalance) {
        vm.startPrank(_user);
        collateral.approve(address(pair), _collateralAmount);
        _pair.borrowAsset(uint128(_amountToBorrow), _collateralAmount, _user);
        _finalShares = pair.userBorrowShares(_user);
        _finalCollateralBalance = pair.userCollateralBalance(_user);
        vm.stopPrank();
    }

    function borrowTokenWithFaucet(
        FraxlendPair _fraxlendPair,
        BorrowAction memory _borrowAction
    ) internal returns (uint256 _finalShares, uint256 _finalCollateralBalance) {
        faucetFunds(_fraxlendPair.collateralContract(), _borrowAction.collateralAmount, _borrowAction.user);
        (_finalShares, _finalCollateralBalance) = borrowToken(
            _fraxlendPair,
            _borrowAction.borrowAmount,
            _borrowAction.collateralAmount,
            _borrowAction.user
        );
    }

    // Repaying
    struct RepayAction {
        FraxlendPair fraxlendPair;
        address user;
        uint256 shares;
    }

    function _preRepayFaucetApprove(RepayAction memory _repayAction) internal {
        IERC20 _asset = IERC20(_repayAction.fraxlendPair.asset());
        faucetFunds(_asset, _repayAction.shares * 2, _repayAction.user);
        _asset.approve(address(_repayAction.fraxlendPair), _repayAction.shares);
    }

    // helper to approve and repay in one step, should have called addInterest before hand

    function repayToken(
        FraxlendPair _fraxlendPair,
        uint256 _sharesToRepay,
        address _user
    ) internal returns (uint256 _finalShares) {
        uint256 _amountToApprove = toBorrowAmount(_sharesToRepay, true);
        asset.approve(address(_fraxlendPair), _amountToApprove);
        _fraxlendPair.repayAsset(_sharesToRepay, _user);
        _finalShares = _fraxlendPair.userBorrowShares(_user);
    }

    function repayTokenWithFaucet(
        FraxlendPair _fraxlendPair,
        uint256 _sharesToRepay,
        address _user
    ) internal returns (uint256 _finalShares) {
        faucetFunds(IERC20(_fraxlendPair.asset()), 2 * _sharesToRepay, _user);
        _finalShares = repayToken(_fraxlendPair, _sharesToRepay, _user);
    }

    function repayTokenWithFaucet(RepayAction memory _repayAction) internal returns (uint256 _finalShares) {
        FraxlendPair _fraxlendPair = _repayAction.fraxlendPair;
        faucetFunds(
            IERC20(_fraxlendPair.asset()),
            _fraxlendPair.toBorrowAmount(_repayAction.shares, true, true),
            _repayAction.user
        );
        _finalShares = repayToken(_fraxlendPair, _repayAction.shares, _repayAction.user);
    }

    // helper to move forward multiple blocks and add interest each time
    function addInterestAndMineBulk(uint256 _blocks) internal returns (uint256 _sumOfInt) {
        _sumOfInt = 0;
        for (uint256 i = 0; i < _blocks; i++) {
            mineOneBlock();
            (uint256 _interestEarned,,,) = pair.addInterest(false);

            _sumOfInt += _interestEarned;
        }
    }

    // Withdraw / Redeeming

    // struct WithdrawAction {
    //     FraxlendPair fraxlendPair;
    //     address user;
    //     uint256 amount;
    // }

    // struct RedeemAction {
    //     FraxlendPair fraxlendPair;
    //     address user;
    //     uint256 shares;
    // }

    // function _preRedeemFaucetApprove(RedeemAction memory _redeemAction) internal {
    //     IERC20 _asset = IERC20(_redeemAction.fraxlendPair.asset());
    //     faucetFunds(_asset, _redeemAction.shares * 2, _redeemAction.user);
    //     _asset.approve(address(_redeemAction.fraxlendPair), _redeemAction.shares * 2);
    // }

    // function redeemTokenWithFaucet(RedeemAction memory _redeemAction) internal returns (uint256 _amount) {
    //     startHoax(_redeemAction.user);
    //     faucetFunds(IERC20(_redeemAction.fraxlendPair.asset()), _redeemAction.shares * 2, _redeemAction.user);
    //     _amount = redeemToken(_redeemAction);
    //     vm.stopPrank();
    // }

    // function redeemToken(RedeemAction memory _redeemAction) internal returns (uint256 _amount) {
    //     _amount = _redeemAction.fraxlendPair.redeem(_redeemAction.shares, _redeemAction.user, _redeemAction.user);
    // }
}
